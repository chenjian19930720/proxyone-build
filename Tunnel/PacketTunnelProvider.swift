import NetworkExtension
import Foundation

final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var engine: Tun2Socks?
    private var server: ProxyServer?

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        TunnelLog.write("==== startTunnel ====")

        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let server = resolveServer(proto: proto) else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }
        guard server.isValid else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }
        self.server = server

        // 解析代理服务器 IP，用于排除路由（防止回环）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                completionHandler(NEVPNError(.configurationInvalid))
                return
            }
            let serverIPs = PacketTunnelProvider.resolveAllIPs(host: server.host)
            guard !serverIPs.isEmpty else {
                TunnelLog.write("无法解析代理服务器 \(server.host)")
                completionHandler(NEVPNError(.configurationInvalid))
                return
            }
            TunnelLog.write("代理服务器 IP: \(serverIPs.joined(separator: ", "))")

            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverIPs[0])
            let ipv4 = NEIPv4Settings(addresses: ["10.7.0.2"], subnetMasks: ["255.255.255.0"])
            var excluded: [NEIPv4Route] = serverIPs.map {
                NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255")
            }
            excluded.append(NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"))
            ipv4.includedRoutes = [NEIPv4Route.default()]
            ipv4.excludedRoutes = excluded
            settings.ipv4Settings = ipv4

            // 隧道内 DNS：这些 UDP 查询会被 UDPRelay 转发到 SOCKS5
            settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
            settings.mtu = 1400

            self.setTunnelNetworkSettings(settings) { [weak self] error in
                if let error {
                    TunnelLog.write("setTunnelNetworkSettings 失败：\(error.localizedDescription)")
                    completionHandler(error)
                    return
                }
                guard let self else { completionHandler(nil); return }
                let engine = Tun2Socks(flow: self.packetFlow, server: server)
                self.engine = engine
                engine.start()
                completionHandler(nil)
                TunnelLog.write("隧道已建立，全局代理生效")
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        TunnelLog.write("==== stopTunnel reason=\(reason.rawValue) ====")
        engine?.stop()
        engine = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let t = engine?.traffic ?? (up: UInt64(0), down: UInt64(0))
        let stats: [String: Any] = [
            "active": engine?.activeConnections ?? 0,
            "up": t.up,
            "down": t.down,
            "server": server?.endpoint ?? "-",
            "targets": engine?.targetsText ?? "",
            "log": TunnelLog.read()
        ]
        let data = (try? JSONSerialization.data(withJSONObject: stats)) ?? Data()
        completionHandler?(data)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        TunnelLog.write("sleep")
        completionHandler()
    }

    override func wake() {
        TunnelLog.write("wake")
    }

    // MARK: - 配置来源
    private func resolveServer(proto: NETunnelProviderProtocol) -> ProxyServer? {
        if let s = SharedStore.decodeFromProvider(proto.providerConfiguration) { return s }
        if let s = SharedStore.selectedServer() { return s }
        return nil
    }

    // MARK: - DNS
    private static func resolveAllIPs(host: String) -> [String] {
        if IPUtil.stringToAddr(host) != nil { return [host] }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let head = res else { return [] }
        defer { freeaddrinfo(res) }
        var out: [String] = []
        var cur: UnsafeMutablePointer<addrinfo>? = head
        while let c = cur {
            if let sa = c.pointee.ai_addr {
                let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                out.append(IPUtil.addrToString(sin.sin_addr.s_addr))
            }
            cur = c.pointee.ai_next
        }
        return Array(Set(out))
    }
}
