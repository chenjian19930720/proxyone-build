import Foundation

/// UDP over SOCKS5（UDP ASSOCIATE）
/// 每个本地 UDP 五元组源分配一个独立 UDP socket，保证返回包可以精确回注。
final class UDPRelay {

    private struct Session {
        var fd: Int32
        var source: DispatchSourceRead
        var lastActive: Date
        var clientIP: UInt32
        var clientPort: UInt16
    }

    private weak var engine: Tun2Socks?
    private let queue: DispatchQueue
    private let server: ProxyServer

    private var controlFD: Int32 = -1
    private var relayAddr: sockaddr_in?
    private var sessions: [String: Session] = [:]
    private var ready = false

    var isReady: Bool { ready }

    init(engine: Tun2Socks, queue: DispatchQueue, server: ProxyServer) {
        self.engine = engine
        self.queue = queue
        self.server = server
    }

    // MARK: 启动 UDP ASSOCIATE
    func start() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let (fd, host, port) = try Socks5.openUDP(server: self.server)
                guard let addr = UDPRelay.makeSockaddr(host: host, port: port) else {
                    close(fd)
                    TunnelLog.write("UDP 中继地址非法 \(host):\(port)")
                    return
                }
                self.queue.async {
                    self.controlFD = fd
                    self.relayAddr = addr
                    self.ready = true
                    TunnelLog.write("UDP ASSOCIATE 就绪，中继 \(host):\(port)")
                }
            } catch {
                TunnelLog.write("UDP ASSOCIATE 失败：\(error)（DNS/UDP 将不可用，可改用 TCP 模式）")
            }
        }
    }

    // MARK: 客户端发出的 UDP
    func handleFromClient(srcIP: UInt32, srcPort: UInt16, dstIP: UInt32, dstPort: UInt16, payload: [UInt8]) {
        guard ready, let relay = relayAddr else { return }
        if IPUtil.isMulticast(dstIP) || IPUtil.isBroadcast(dstIP) { return }

        let key = "\(srcIP):\(srcPort)"
        var session = sessions[key]

        if session == nil {
            guard let created = makeSession(srcIP: srcIP, srcPort: srcPort) else { return }
            sessions[key] = created
            session = created
        }
        guard var s = session else { return }
        s.lastActive = Date()
        sessions[key] = s

        var datagram: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        withUnsafeBytes(of: dstIP) { datagram.append(contentsOf: $0) }
        datagram.append(UInt8(dstPort >> 8))
        datagram.append(UInt8(dstPort & 0xFF))
        datagram.append(contentsOf: payload)

        var addr = relay
        let n = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                datagram.withUnsafeBytes {
                    sendto(s.fd, $0.baseAddress, datagram.count, 0, sa,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if n < 0 {
            TunnelLog.write("UDP 发送失败 errno=\(errno)")
        }
    }

    private func makeSession(srcIP: UInt32, srcPort: UInt16) -> Session? {
        guard let relay = relayAddr else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        var addr = relay
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else { close(fd); return nil }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.readFromServer(fd: fd)
        }
        src.setCancelHandler { close(fd) }
        src.resume()

        return Session(fd: fd, source: src, lastActive: Date(), clientIP: srcIP, clientPort: srcPort)
    }

    // MARK: 服务器返回的 UDP
    private func readFromServer(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 65535)
        let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 65535, 0) }
        guard n > 8 else { return }
        buf.removeLast(65535 - n)

        guard buf[0] == 0, buf[1] == 0 else { return }
        let atyp = buf[3]
        var offset = 4
        var srcIP: UInt32 = 0
        switch atyp {
        case 0x01:
            guard buf.count >= 10 else { return }
            withUnsafeMutableBytes(of: &srcIP) { $0.copyBytes(from: buf[4..<8]) }
            offset = 8
        case 0x04:
            return   // 本实现的隧道只处理 IPv4
        case 0x03:
            guard buf.count >= 5 else { return }
            let len = Int(buf[4])
            guard buf.count >= 5 + len + 2 else { return }
            let host = String(bytes: buf[5..<(5 + len)], encoding: .utf8) ?? ""
            srcIP = IPUtil.stringToAddr(host) ?? 0
            offset = 5 + len
        default:
            return
        }
        guard buf.count >= offset + 2 else { return }
        let srcPort = UInt16(buf[offset]) << 8 | UInt16(buf[offset + 1])
        let payload = Array(buf[(offset + 2)...])
        // 单个 IP 包不能超过 MTU，超了就丢（DNS 响应正常都在 1300 以内）
        guard payload.count <= 1300 else {
            TunnelLog.write("UDP 响应过大 \(payload.count)B，丢弃")
            return
        }

        // 找到对应会话（按 fd 反查）
        guard let session = sessions.values.first(where: { $0.fd == fd }) else { return }
        let packet = PacketBuilder.udp(src: srcIP, dst: session.clientIP,
                                       srcPort: srcPort, dstPort: session.clientPort,
                                       payload: payload)
        engine?.writeToTun([packet])
    }

    // MARK: 维护
    func housekeeping() {
        let now = Date()
        for (key, s) in sessions where now.timeIntervalSince(s.lastActive) > 120 {
            s.source.cancel()
            sessions.removeValue(forKey: key)
        }
    }

    func stop() {
        for (_, s) in sessions { s.source.cancel() }
        sessions.removeAll()
        if controlFD >= 0 { close(controlFD); controlFD = -1 }
        ready = false
    }

    static func makeSockaddr(host: String, port: UInt16) -> sockaddr_in? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }
        return addr
    }
}
