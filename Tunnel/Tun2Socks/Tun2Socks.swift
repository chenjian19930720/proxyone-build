import Foundation
import NetworkExtension

/// 极简 tun2socks：把 utun 里的 IPv4 流量转成 SOCKS5。
final class Tun2Socks {

    private let flow: NEPacketTunnelFlow
    private let server: ProxyServer
    let queue = DispatchQueue(label: "com.example.proxyone.tun2socks", qos: .userInitiated)

    private var relays: [String: TCPRelay] = [:]
    private var udp: UDPRelay?
    private var dns: DNSRelay?
    private var running = false
    private var timer: DispatchSourceTimer?
    private var blockedAddresses: Set<UInt32> = []
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var bytesUp: UInt64 = 0
    private var bytesDown: UInt64 = 0

    /// 累计流量（上行=手机发出，下行=服务器回给手机）
    var traffic: (up: UInt64, down: UInt64) {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return (bytesUp, bytesDown) }
        return queue.sync { (bytesUp, bytesDown) }
    }

    init(flow: NEPacketTunnelFlow, server: ProxyServer) {
        self.flow = flow
        self.server = server
        queue.setSpecific(key: queueKey, value: 1)
        if let ip = IPUtil.stringToAddr(server.host) { blockedAddresses.insert(ip) }
    }

    // MARK: 生命周期
    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            // 隧道自身网段与代理服务器地址不进入隧道逻辑
            for ip in ["10.7.0.1", "10.7.0.2"] {
                if let a = IPUtil.stringToAddr(ip) { self.blockedAddresses.insert(a) }
            }
            let udp = UDPRelay(engine: self, queue: self.queue, server: self.server)
            self.udp = udp
            udp.start()
            self.dns = DNSRelay(engine: self, queue: self.queue, server: self.server)
            self.startTimer()
            self.readLoop()
            TunnelLog.write("Tun2Socks 已启动 → \(self.server.endpoint)")
        }
    }

    func stop() {
        queue.async {
            self.running = false
            for (_, r) in self.relays { r.forceClose() }
            self.relays.removeAll()
            self.udp?.stop()
            self.udp = nil
            self.dns = nil
            self.timer?.cancel()
            self.timer = nil
            TunnelLog.write("Tun2Socks 已停止")
        }
    }

    // MARK: 读包
    private func readLoop() {
        flow.readPackets { [weak self] packets, _ in
            guard let self, self.running else { return }
            self.queue.async {
                for p in packets { self.handle([UInt8](p)) }
                if self.running { self.readLoop() }
            }
        }
    }

    // MARK: 分发
    private func handle(_ bytes: [UInt8]) {
        bytesUp &+= UInt64(bytes.count)
        guard let packet = PacketParser.parseIPv4(bytes) else { return }
        if blockedAddresses.contains(packet.dstIP) { return }
        if IPUtil.isMulticast(packet.dstIP) || IPUtil.isBroadcast(packet.dstIP) { return }

        switch packet.proto {
        case 6:
            guard let tcp = PacketParser.parseTCP(packet.payload) else { return }
            handleTCP(packet: packet, tcp: tcp)
        case 17:
            guard let udpHeader = PacketParser.parseUDP(packet.payload) else { return }
            // 服务器不支持 UDP ASSOCIATE 时，DNS 走 "DNS over TCP"
            if udpHeader.dstPort == 53, udp?.isReady != true {
                dns?.forward(query: udpHeader.payload, srcIP: packet.srcIP, srcPort: udpHeader.srcPort,
                             dstIP: packet.dstIP, dstPort: udpHeader.dstPort)
            } else {
                udp?.handleFromClient(srcIP: packet.srcIP, srcPort: udpHeader.srcPort,
                                      dstIP: packet.dstIP, dstPort: udpHeader.dstPort,
                                      payload: udpHeader.payload)
            }
        default:
            break
        }
    }

    private func handleTCP(packet: IPv4Packet, tcp: TCPHeader) {
        let key = TCPRelay.makeKey(clientIP: packet.srcIP, clientPort: tcp.srcPort,
                                   dstIP: packet.dstIP, dstPort: tcp.dstPort)

        if let relay = relays[key] {
            relay.handleFromClient(tcp: tcp)
            return
        }

        // 新连接
        if tcp.flags & TCPFlags.syn != 0 && tcp.flags & TCPFlags.ack == 0 {
            let dstName = IPUtil.addrToString(packet.dstIP)
            let relay = TCPRelay(engine: self, queue: queue,
                                 clientIP: packet.srcIP, clientPort: tcp.srcPort,
                                 dstHost: dstName, dstIP: packet.dstIP, dstPort: tcp.dstPort,
                                 clientSeq: tcp.seq)
            relays[key] = relay
            relay.connect(server: server)
        }
    }

    // MARK: 写包
    func writeToTun(_ packets: [[UInt8]]) {
        guard !packets.isEmpty else { return }
        for p in packets { bytesDown &+= UInt64(p.count) }
        let datas = packets.map { Data($0) }
        flow.writePackets(datas, withProtocols: datas.map { _ in NSNumber(value: AF_INET) })
    }

    func removeRelay(_ relay: TCPRelay) {
        queue.async {
            self.relays.removeValue(forKey: relay.key)
        }
    }

    // MARK: 定时维护
    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 15, repeating: 15)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for (_, r) in self.relays { r.housekeeping() }
            self.udp?.housekeeping()
        }
        t.resume()
        timer = t
    }

    var activeConnections: Int {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return relays.count }
        return queue.sync { relays.count }
    }
}
