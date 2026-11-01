import Foundation
import NetworkExtension
import Combine

@MainActor
final class TunnelManager: ObservableObject {

    static let tunnelBundleID = "com.example.proxyone.tunnel"

    @Published var status: NEVPNStatus = .invalid
    @Published var servers: [ProxyServer] = SharedStore.loadServers()
    @Published var selectedID: UUID? = SharedStore.selectedServerID {
        didSet { SharedStore.selectedServerID = selectedID }
    }
    @Published var lastError: String?
    @Published var activeConnections: Int = 0
    @Published var tunnelLog: String = ""

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    var isBusy: Bool { status == .connecting || status == .reasserting || status == .disconnecting }
    var isOn: Bool { status == .connected || status == .connecting || status == .reasserting }

    var statusText: String {
        switch status {
        case .connected: return "已连接 · 全局代理生效"
        case .connecting: return "正在连接…"
        case .reasserting: return "正在重连…"
        case .disconnecting: return "正在断开…"
        case .disconnected: return "未连接"
        case .invalid: return "未配置"
        @unknown default: return "未知"
        }
    }

    var currentServer: ProxyServer? {
        servers.first { $0.id == selectedID } ?? servers.first
    }

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let conn = note.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.status = conn.status }
        }
    }

    deinit {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    }

    // MARK: 加载已有配置
    func load() async {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let existing = all.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.tunnelBundleID
            }
            manager = existing
            status = existing?.connection.status ?? .invalid
            if servers.isEmpty {
                servers = []
            }
        } catch {
            lastError = "读取 VPN 配置失败：\(error.localizedDescription)"
        }
    }

    // MARK: 保存节点列表
    func persistServers() {
        SharedStore.saveServers(servers)
        if selectedID == nil { selectedID = servers.first?.id }
    }

    func upsert(_ server: ProxyServer) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
        persistServers()
    }

    func delete(_ server: ProxyServer) {
        servers.removeAll { $0.id == server.id }
        if selectedID == server.id { selectedID = servers.first?.id }
        persistServers()
    }

    // MARK: 一键开 / 关
    func toggle() async {
        if isOn { await stop() } else { await start() }
    }

    func start() async {
        guard let server = currentServer, server.isValid else {
            lastError = "先在「节点」里填好 SOCKS5 服务器地址和端口"
            return
        }
        lastError = nil
        do {
            let manager = try await ensureManager(server: server)
            try manager.connection.startVPNTunnel()
            status = manager.connection.status
        } catch {
            lastError = "启动失败：\(Self.explain(error))"
        }
    }

    func stop() async {
        guard let manager else { return }
        manager.connection.stopVPNTunnel()
        status = manager.connection.status
    }

    private func ensureManager(server: ProxyServer) async throws -> NETunnelProviderManager {
        // 让 App Group 里的配置与将要写入的一致
        SharedStore.saveServers(servers)
        SharedStore.selectedServerID = server.id

        let manager = self.manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = server.endpoint
        proto.providerConfiguration = SharedStore.encodeForProvider(server)
        proto.disconnectOnSleep = false

        manager.protocolConfiguration = proto
        manager.localizedDescription = "ProxyOne · \(server.name)"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false

        try await manager.saveToPreferences()
        // 保存后必须重新加载才能启动
        try await manager.loadFromPreferences()
        self.manager = manager
        return manager
    }

    // MARK: 统计 / 日志
    func refreshStats() async {
        guard let session = manager?.connection as? NETunnelProviderSession,
              status == .connected else {
            activeConnections = 0
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                try session.sendProviderMessage(Data("stats".utf8)) { data in
                    if let data,
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Task { @MainActor in
                            self.activeConnections = obj["active"] as? Int ?? 0
                            self.tunnelLog = obj["log"] as? String ?? ""
                        }
                    }
                    cont.resume()
                }
            } catch {
                cont.resume()
            }
        }
    }

    // MARK: 延迟测试（直连 SOCKS5 端口，测 TCP 握手耗时）
    func ping(_ server: ProxyServer) async -> Int? {
        await Self.pingStatic(server)
    }

    nonisolated static func pingStatic(_ server: ProxyServer) async -> Int? {
        guard server.isValid else { return nil }
        let start = Date()
        let ok: Bool = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(server.host, String(server.port), &hints, &res) == 0,
                      let info = res else { cont.resume(returning: false); return }
                defer { freeaddrinfo(res) }
                let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
                guard fd >= 0 else { cont.resume(returning: false); return }
                defer { close(fd) }
                var tv = timeval(tv_sec: 3, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                let rc = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
                cont.resume(returning: rc == 0)
            }
        }
        guard ok else { return nil }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    // MARK: - 线路操作

    func fastestNodes(limit: Int) -> [ProxyServer] {
        let measured = servers.filter { $0.latency != nil }
        let sorted = measured.sorted { ($0.latency ?? 99999) < ($1.latency ?? 99999) }
        return Array(sorted.prefix(limit))
    }

    func importNodes(_ nodes: [ProxyServer]) {
        guard !nodes.isEmpty else { return }
        var seen = Set(servers.map { "\($0.host):\($0.port)" })
        for n in nodes {
            let key = "\(n.host):\(n.port)"
            if seen.contains(key) { continue }
            seen.insert(key)
            servers.append(n)
        }
        persistServers()
        if selectedID == nil { selectedID = servers.first?.id }
        Task { await refreshLatencies() }
    }

    /// 选中一条线路；若当前已连接，则断开重连到新线路
    func activate(_ server: ProxyServer) async {
        let wasOn = isOn
        selectedID = server.id
        persistServers()
        guard wasOn else { return }
        await stop()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await start()
    }

    /// 并发测所有线路的握手延迟
    func refreshLatencies() async {
        let snapshot = servers
        guard !snapshot.isEmpty else { return }
        var results: [UUID: Int] = [:]
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for s in snapshot {
                group.addTask { (s.id, await TunnelManager.pingStatic(s)) }
            }
            for await (id, ms) in group {
                if let ms { results[id] = ms }
            }
        }
        for i in servers.indices {
            servers[i].latency = results[servers[i].id]
        }
        persistServers()
    }

    // MARK: - 诊断

    struct ProbeResult {
        var ok: Bool
        var ms: Int
        var detail: String
    }

    /// 走隧道（或直连）请求出口 IP
    func checkExitIP() async -> String {
        guard var comps = URLComponents(string: "https://api.ipify.org") else { return "?" }
        comps.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = comps.url else { return "?" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = obj["ip"] as? String {
                return ip
            }
            return String(data: data, encoding: .utf8) ?? "?"
        } catch {
            return "请求失败：\(error.localizedDescription)"
        }
    }

    /// 完整 SOCKS5 握手探测，能区分是网络问题还是认证问题
    func probe(_ server: ProxyServer) async -> ProbeResult {
        guard server.isValid else {
            return ProbeResult(ok: false, ms: 0, detail: "地址或端口为空")
        }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: Self.probeBlocking(server))
            }
        }
    }

    nonisolated private static func probeBlocking(_ server: ProxyServer) -> ProbeResult {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(server.host, String(server.port), &hints, &res) == 0, let info = res else {
            return ProbeResult(ok: false, ms: 0, detail: "DNS 解析失败：\(server.host)")
        }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return ProbeResult(ok: false, ms: 0, detail: "创建 socket 失败") }
        defer { close(fd) }

        var tv = timeval(tv_sec: 6, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        let t0 = Date()
        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
            return ProbeResult(ok: false, ms: 0,
                               detail: "TCP 连不上 \(server.endpoint)：\(String(cString: strerror(errno)))")
        }
        let connectMs = Int(Date().timeIntervalSince(t0) * 1000)

        let useAuth = !server.username.isEmpty
        let greeting: [UInt8] = useAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]
        guard writeAll(fd, greeting) else {
            return ProbeResult(ok: false, ms: connectMs, detail: "握手写入失败")
        }
        guard let resp = readExactly(fd, 2) else {
            return ProbeResult(ok: false, ms: connectMs,
                               detail: "端口通但没有 SOCKS5 响应（也许该端口不是 SOCKS5）")
        }
        guard resp[0] == 0x05 else {
            return ProbeResult(ok: false, ms: connectMs,
                               detail: "服务器返回版本 0x\(String(resp[0], radix: 16))，不是 SOCKS5")
        }
        if resp[1] == 0x02 {
            let u = Array(server.username.utf8)
            let p = Array(server.password.utf8)
            var auth: [UInt8] = [0x01, UInt8(u.count)]
            auth.append(contentsOf: u)
            auth.append(UInt8(p.count))
            auth.append(contentsOf: p)
            guard writeAll(fd, auth), let r = readExactly(fd, 2), r[1] == 0x00 else {
                return ProbeResult(ok: false, ms: connectMs, detail: "用户名或密码错误")
            }
        } else if resp[1] == 0xFF {
            return ProbeResult(ok: false, ms: connectMs, detail: "服务器不接受任何认证方式")
        }
        return ProbeResult(ok: true, ms: connectMs, detail: "SOCKS5 正常，握手 \(connectMs) ms")
    }

    nonisolated private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, bytes.count - sent) }
            if n > 0 { sent += n; continue }
            if errno == EINTR { continue }
            return false
        }
        return true
    }

    nonisolated private static func readExactly(_ fd: Int32, _ count: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: got), count - got) }
            if n > 0 { got += n; continue }
            if errno == EINTR { continue }
            return nil
        }
        return buf
    }

    /// 把 NEVPNErrorDomain 的错误码翻译成人话
    nonisolated static func explain(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == "NEVPNErrorDomain" else { return error.localizedDescription }
        switch ns.code {
        case 1: return "配置无效：检查服务器地址/端口，或扩展未正确签名"
        case 2: return "配置被禁用：到 设置→通用→VPN与设备管理 里重新启用"
        case 3: return "配置已过期"
        case 4: return "无权限启动 VPN：证书缺少 Network Extension 能力"
        case 5: return "另一个 VPN 正在连接"
        default: return "VPN 错误 \(ns.code)：\(ns.localizedDescription)"
        }
    }
}
