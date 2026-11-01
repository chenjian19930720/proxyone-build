import Foundation

/// 当 SOCKS5 服务器不支持 UDP ASSOCIATE 时，把 DNS(UDP 53) 自动降级成
/// "DNS over TCP 53 通过 SOCKS5 CONNECT 转发"，保证域名解析仍然可用。
final class DNSRelay {

    private weak var engine: Tun2Socks?
    private let queue: DispatchQueue
    private let server: ProxyServer
    private var pending = 0
    private let maxConcurrent = 12

    init(engine: Tun2Socks, queue: DispatchQueue, server: ProxyServer) {
        self.engine = engine
        self.queue = queue
        self.server = server
    }

    func forward(query: [UInt8], srcIP: UInt32, srcPort: UInt16,
                 dstIP: UInt32, dstPort: UInt16) {
        guard query.count >= 12, query.count < 65535 else { return }
        if pending >= maxConcurrent {
            TunnelLog.write("DNS 并发已满，丢弃查询")
            return
        }
        pending += 1
        let host = IPUtil.addrToString(dstIP)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            defer { self.queue.async { self.pending -= 1 } }
            do {
                let fd = try Socks5.openTCP(server: self.server, dstHost: host, dstPort: dstPort, timeout: 6)
                defer { close(fd) }

                let length: [UInt8] = [UInt8(query.count >> 8), UInt8(query.count & 0xFF)]
                try Socks5.writeAll(fd, length + query)

                let head = try Socks5.readExactly(fd, 2)
                let respLen = Int(head[0]) << 8 | Int(head[1])
                guard respLen > 12, respLen <= 65535 else {
                    throw Socks5Error.handshake("DNS 响应长度异常 \(respLen)")
                }
                let resp = try Socks5.readExactly(fd, respLen)
                self.queue.async {
                    let packet = PacketBuilder.udp(src: dstIP, dst: srcIP,
                                                   srcPort: dstPort, dstPort: srcPort,
                                                   payload: resp)
                    self.engine?.writeToTun([packet])
                }
            } catch {
                TunnelLog.write("DNS/TCP 转发失败 \(host):\(dstPort) — \(error)")
            }
        }
    }
}
