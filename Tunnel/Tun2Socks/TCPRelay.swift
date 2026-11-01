import Foundation

/// 一条 TCP 流：本地 App ⇄ (utun) ⇄ SOCKS5 服务器 ⇄ 目标
final class TCPRelay {

    enum State: Equatable { case connecting, established, serverClosed, closed }

    let key: String
    let clientIP: UInt32
    let clientPort: UInt16
    let dstHost: String
    let dstIP: UInt32
    let dstPort: UInt16

    private weak var engine: Tun2Socks?
    private let queue: DispatchQueue

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    private var sndISN: UInt32 = UInt32.random(in: 1...UInt32.max - 1000)
    private var sndNxt: UInt32 = 0            // 我们发出的下一序号（相对本地客户端）
    private var rcvNxt: UInt32 = 0            // 期望的客户端下一序号
    private var clientWindow: UInt16 = 65535

    private var state: State = .connecting
    private var lastActivity = Date()
    private var unacked: [(seq: UInt32, data: [UInt8], at: Date)] = []
    private var closeAfterFlush = false

    init(engine: Tun2Socks, queue: DispatchQueue,
         clientIP: UInt32, clientPort: UInt16,
         dstHost: String, dstIP: UInt32, dstPort: UInt16,
         clientSeq: UInt32) {
        self.engine = engine
        self.queue = queue
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.dstHost = dstHost
        self.dstIP = dstIP
        self.dstPort = dstPort
        self.rcvNxt = clientSeq &+ 1
        self.sndNxt = sndISN &+ 1
        self.key = TCPRelay.makeKey(clientIP: clientIP, clientPort: clientPort, dstIP: dstIP, dstPort: dstPort)
    }

    static func makeKey(clientIP: UInt32, clientPort: UInt16, dstIP: UInt32, dstPort: UInt16) -> String {
        "\(clientIP):\(clientPort)->\(dstIP):\(dstPort)"
    }

    var isExpired: Bool { Date().timeIntervalSince(lastActivity) > 300 }

    // MARK: 连接 SOCKS5
    func connect(server: ProxyServer) {
        let host = dstHost
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let fd = try Socks5.openTCP(server: server, dstHost: host, dstPort: self.dstPort)
                self.queue.async { self.attach(fd) }
            } catch {
                TunnelLog.write("TCP 连接失败 \(host):\(self.dstPort) — \(error)")
                self.queue.async { self.abort() }
            }
        }
    }

    private func attach(_ fd: Int32) {
        guard state == .connecting else { close(fd); return }
        self.fd = fd
        // 非阻塞读
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var zero = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &zero, socklen_t(MemoryLayout<timeval>.size))

        state = .established
        lastActivity = Date()

        // 回 SYN-ACK
        send(seq: sndISN, ack: rcvNxt, flags: TCPFlags.syn | TCPFlags.ack, payload: [])

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.readFromServer() }
        src.setCancelHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            close(self.fd)
            self.fd = -1
        }
        source = src
        src.resume()
    }

    // MARK: 客户端 → SOCKS
    func handleFromClient(tcp: TCPHeader) {
        lastActivity = Date()
        clientWindow = tcp.window

        // 客户端确认了我们的数据
        if tcp.flags & TCPFlags.ack != 0 {
            dropAcked(tcp.ack)
        }

        if tcp.flags & TCPFlags.rst != 0 {
            terminate()
            return
        }

        if state == .connecting {
            // 还没连上 SOCKS，忽略数据（客户端会重传）
            return
        }

        let payload = tcp.payload
        if !payload.isEmpty {
            if tcp.seq == rcvNxt {
                rcvNxt = rcvNxt &+ UInt32(payload.count)
                writeToServer(payload)
                send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.ack, payload: [])
            } else if tcp.seq &- 1 == rcvNxt {   // 重传的 FIN 等边界情况
                send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.ack, payload: [])
            } else {
                // 乱序或重复：直接 ACK 当前期望序号，催客户端重传
                send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.ack, payload: [])
            }
        }

        if tcp.flags & TCPFlags.fin != 0 {
            if tcp.seq &+ UInt32(payload.count) == rcvNxt {
                rcvNxt = rcvNxt &+ 1
                if fd >= 0 { shutdown(fd, SHUT_WR) }
                send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.ack, payload: [])
                if state == .serverClosed { terminate() }
            }
        }
    }

    private func writeToServer(_ data: [UInt8]) {
        guard fd >= 0 else { return }
        var sent = 0
        while sent < data.count {
            let n = data[sent...].withUnsafeBytes { write(fd, $0.baseAddress, data.count - sent) }
            if n > 0 { sent += n; continue }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // 内核发送缓冲满，剩余部分丢弃（对端会因序号断档重传）
                TunnelLog.write("TCP 写缓冲满，丢弃 \(data.count - sent) 字节")
                return
            }
            terminate()
            return
        }
    }

    // MARK: SOCKS → 客户端
    private func readFromServer() {
        guard fd >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 16384)
        let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, 16384) }
        if n > 0 {
            lastActivity = Date()
            buf.removeLast(16384 - n)
            send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.psh | TCPFlags.ack, payload: buf)
            sndNxt = sndNxt &+ UInt32(n)
            unacked.append((sndNxt &- UInt32(n), buf, Date()))
            if unacked.count > 512 { unacked.removeFirst(unacked.count - 512) }
        } else if n == 0 {
            // 服务器正常关闭
            state = .serverClosed
            send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.fin | TCPFlags.ack, payload: [])
            sndNxt = sndNxt &+ 1
            source?.cancel()
            source = nil
            // 已向客户端发 FIN，等客户端回 FIN 后 terminate()
        } else {
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return }
            terminate()
        }
    }

    private func dropAcked(_ ack: UInt32) {
        guard !unacked.isEmpty else { return }
        unacked.removeAll { $0.seq &+ UInt32($0.data.count) <= ack && seqLE($0.seq, ack) }
    }

    private func seqLE(_ a: UInt32, _ b: UInt32) -> Bool { Int32(bitPattern: a &- b) <= 0 }

    // MARK: 发包
    private func send(seq: UInt32, ack: UInt32, flags: UInt8, payload: [UInt8]) {
        let packet = PacketBuilder.tcp(src: dstIP, dst: clientIP,
                                       srcPort: dstPort, dstPort: clientPort,
                                       seq: seq, ack: ack,
                                       flags: flags, window: 65535,
                                       payload: payload)
        engine?.writeToTun([packet])
    }

    // MARK: 关闭
    private func abort() {
        send(seq: sndNxt, ack: rcvNxt, flags: TCPFlags.rst | TCPFlags.ack, payload: [])
        terminate()
    }

    private func terminate() {
        guard state != .closed else { return }
        state = .closed
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
        engine?.removeRelay(self)
    }

    func forceClose() { terminate() }

    /// 清理已确认数据的重传缓冲（由引擎定时调用）
    func housekeeping() {
        if isExpired { terminate() }
    }
}
