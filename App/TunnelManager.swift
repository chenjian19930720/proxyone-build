import Foundation
import NetworkExtension
import Network
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
    @Published var connectedSince: Date?
    @Published var bytesUp: UInt64 = 0
    @Published var bytesDown: UInt64 = 0
    @Published var lastIPError: String = ""
    @Published var exitIPLocation: String = ""
    @Published var recentTargets: String = ""
    @Published var statsError: String = ""
    @Published var latencyRefreshing = false
    @Published var alwaysOn: Bool = SharedStore.alwaysOn
    @Published var networkUp: Bool = true
    @Published var syncConfig: SyncConfig = SharedStore.syncConfig
    @Published var syncing = false
    @Published var accountExpires: TimeInterval = SharedStore.userExpires

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()

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
            Task { @MainActor in
                guard let self else { return }
                self.status = conn.status
                switch conn.status {
                case .connected:
                    if self.connectedSince == nil { self.connectedSince = Date() }
                case .disconnected, .invalid:
                    self.connectedSince = nil
                    self.bytesUp = 0
                    self.bytesDown = 0
                default:
                    break
                }
            }
        }

        // 网络变化：断网时记录，恢复后如果开了「强制保持连接」就立刻拉起隧道
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.handlePathChange(up) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.example.proxyone.path"))
    }

    private func handlePathChange(_ up: Bool) {
        let recovered = up && !networkUp
        networkUp = up
        guard up, alwaysOn else { return }        // 有网络：若隧道没连上（含刚恢复网络），补一次启动
        guard recovered || status == .disconnected || status == .invalid else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if alwaysOn && status != .connected { await start() }
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
        guard !isBusy else { return }        // 连接/断开过程中忽略重复点击
        if isOn { await stop() } else { await start() }
    }

    func start() async {
        guard !isBusy else { return }
        guard let server = currentServer, server.isValid else {
            lastError = "先在「线路」里填好 SOCKS5 服务器地址和端口"
            return
        }
        guard server.proto == "socks5" else {
            lastError = "\(server.proto.uppercased()) 协议暂未支持，当前版本只支持 SOCKS5"
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

    func stop(preserveAlwaysOn: Bool = false) async {
        guard let manager else { return }
        // 手动断开等同于关掉「强制保持连接」；
        // 但切换线路时不能关，否则开关会自己弹回去。
        if alwaysOn && !preserveAlwaysOn {
            alwaysOn = false
            SharedStore.alwaysOn = false
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            try? await manager.saveToPreferences()
        }
        manager.connection.stopVPNTunnel()
        status = manager.connection.status
    }

    /// 强制保持连接：断网自动重连，网络恢复立即连上，App 被杀也由系统维持
    func setAlwaysOn(_ on: Bool) async {
        alwaysOn = on
        SharedStore.alwaysOn = on

        guard let m = manager else {
            if on { await start() }
            return
        }
        m.isOnDemandEnabled = on
        m.onDemandRules = on ? [Self.keepAliveRule()] : []
        do {
            try await m.saveToPreferences()
            try? await m.loadFromPreferences()
        } catch {
            lastError = "保存「保持连接」失败：\(Self.explain(error))"
            return
        }
        if on && status != .connected && status != .connecting {
            await start()
        }
    }

    nonisolated static func keepAliveRule() -> NEOnDemandRule {
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        return rule
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
        manager.localizedDescription = "待续IP系统 · \(server.name)"
        manager.isEnabled = true
        manager.isOnDemandEnabled = alwaysOn
        manager.onDemandRules = alwaysOn ? [Self.keepAliveRule()] : []

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
            statsError = status == .connected ? "拿不到会话" : ""
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // 超时保护：provider 没响应时不要让协程永远挂着
            let done = NSLock()
            var finished = false
            func finish() {
                done.lock()
                if finished { done.unlock(); return }
                finished = true
                done.unlock()
                cont.resume()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                done.lock()
                let already = finished
                done.unlock()
                if !already {
                    Task { @MainActor in self.statsError = "扩展 5 秒未响应" }
                }
                finish()
            }
            do {
                try session.sendProviderMessage(Data("stats".utf8)) { data in
                    if let data,
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Task { @MainActor in
                            self.activeConnections = obj["active"] as? Int ?? 0
                            self.bytesUp = (obj["up"] as? NSNumber)?.uint64Value ?? 0
                            self.bytesDown = (obj["down"] as? NSNumber)?.uint64Value ?? 0
                            self.recentTargets = obj["targets"] as? String ?? ""
                            self.statsError = ""
                        }
                    } else {
                        Task { @MainActor in self.statsError = "扩展没有返回数据" }
                    }
                    finish()
                }
            } catch {
                Task { @MainActor in self.statsError = error.localizedDescription }
                finish()
            }
        }
    }

    /// 单独拉日志（日志较大，不跟流量一起传）
    func pullLog() async {
        guard let session = manager?.connection as? NETunnelProviderSession,
              status == .connected else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                try session.sendProviderMessage(Data("log".utf8)) { data in
                    if let data,
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let log = obj["log"] as? String {
                        Task { @MainActor in self.tunnelLog = log }
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

                // 非阻塞 connect + poll：SO_SNDTIMEO 管不住 connect，
                // 老写法在不通的线路上会卡 75 秒，整个刷新就假死了。
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

                let rc = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
                if rc == 0 { cont.resume(returning: true); return }
                guard errno == EINPROGRESS else { cont.resume(returning: false); return }

                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let pr = poll(&pfd, 1, 2500)          // 硬超时 2.5 秒
                guard pr > 0 else { cont.resume(returning: false); return }

                var soErr: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
                cont.resume(returning: soErr == 0)
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
        await stop(preserveAlwaysOn: true)
        try? await Task.sleep(nanoseconds: 400_000_000)
        await start()
    }

    /// 并发测所有线路的握手延迟
    func refreshLatencies() async {
        guard !latencyRefreshing else { return }      // 防重入：连点刷新不会叠任务
        latencyRefreshing = true
        defer { latencyRefreshing = false }

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
        // 不用索引遍历：await 期间 servers 可能被同步逻辑替换，按 id 回写最安全
        var updated = servers
        for i in updated.indices {
            let id = updated[i].id
            if snapshot.contains(where: { $0.id == id }) {
                updated[i].latency = results[id]
            }
        }
        servers = updated
        persistServers()
    }

    // MARK: - 诊断

    struct ProbeResult {
        var ok: Bool
        var ms: Int
        var detail: String
    }

    /// 拉取后台配置（离线密码、公告），启动时调用
    func pullConfig() async {
        let base = syncConfig.baseURL.isEmpty ? AppConfig.defaultBackend : syncConfig.baseURL
        guard !base.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let cfg = try? await SyncService.fetchConfig(base: base) else { return }
        if let h = cfg.offline_password_sha256, !h.isEmpty {
            SharedStore.offlineHash = h
        }
        SharedStore.announcement = cfg.announcement ?? ""
        SharedStore.latestVersion = cfg.app_version ?? ""
        SharedStore.updateURL = cfg.app_update_url ?? ""
    }

    /// 是否有新版本
    var hasUpdate: Bool {
        let latest = SharedStore.latestVersion
        guard !latest.isEmpty else { return false }
        return latest.compare(AppConfig.appVersion, options: .numeric) == .orderedDescending
    }

    /// 走隧道（或直连）请求出口 IP，失败时返回具体原因
    func checkExitIP() async -> String {
        // 先用 myip.ipip.net：它同时给出 IP 和归属地
        let a = await queryCNIP()
        if let ip = a.0 {
            exitIPLocation = a.1
            lastIPError = ""
            return ip
        }
        // 兜底用纯 IP 接口，归属地留空
        let b = await queryPlainIP()
        if let ip = b.0 {
            exitIPLocation = ""
            lastIPError = ""
            return ip
        }
        lastIPError = a.2.isEmpty ? b.1 : a.2
        return "获取失败"
    }

    /// myip.ipip.net：返回「当前 IP：x.x.x.x 来自于：中国 广东 广州 电信」
    private func queryCNIP() async -> (String?, String, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try SimpleHTTP.request("http://myip.ipip.net", timeout: 10)
                    let text = String(data: r.body, encoding: .utf8) ?? ""

                    var ip: String?
                    for token in text.split(whereSeparator: { " ：:，,　\t\n".contains($0) }) {
                        let t = String(token)
                        if Self.isIPv4(t) { ip = t; break }
                    }
                    guard let found = ip else {
                        cont.resume(returning: (nil, "",
                                                "myip.ipip.net 未找到 IP（HTTP \(r.status)）"))
                        return
                    }
                    var loc = ""
                    if let rng = text.range(of: "来自于：") {
                        loc = String(text[rng.upperBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "  ", with: " ")
                    }
                    cont.resume(returning: (found, loc, ""))
                } catch {
                    cont.resume(returning: (nil, "", "myip.ipip.net 失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    /// ip.3322.net：直接返回纯 IP 文本（没有归属地）
    private func queryPlainIP() async -> (String?, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try SimpleHTTP.request("http://ip.3322.net", timeout: 10)
                    let s = (String(data: r.body, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if Self.isIPv4(s) { cont.resume(returning: (s, "")); return }
                    cont.resume(returning: (nil, "ip.3322.net 异常 HTTP \(r.status)：\(s.prefix(40))"))
                } catch {
                    cont.resume(returning: (nil, "ip.3322.net 失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    nonisolated static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for p in parts {
            guard let n = Int(p), n >= 0, n <= 255 else { return false }
        }
        return true
    }

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
        guard SocketUtil.connectWithTimeout(fd: fd,
                                            addr: info.pointee.ai_addr,
                                            len: info.pointee.ai_addrlen,
                                            timeoutMs: 5000) else {
            return ProbeResult(ok: false, ms: 0,
                               detail: "TCP 连不上 \(server.endpoint)：超时或不可达")
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

    // MARK: - 账户 / 后台同步

    func login(account: String, password: String, backend: String) async -> String? {
        let acc = account.trimmingCharacters(in: .whitespaces)
        guard !acc.isEmpty else { return "请输入账号" }
        let base = backend.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return "请填写服务器地址（管理员会提供）" }
        guard !password.isEmpty else { return "请输入密码" }

        var cfg = syncConfig
        cfg.baseURL = base
        cfg.username = acc

        do {
            let (token, info) = try await SyncService.login(base: base, user: acc, pass: password)
            cfg.password = password
            cfg.token = token
            cfg.lastSync = 0
            cfg.lastMessage = "登录成功"
            saveSync(cfg)
            SharedStore.accountName = acc
            SharedStore.userExpires = info?.expires ?? 0
            SharedStore.userGroups = info?.group ?? ""
            accountExpires = info?.expires ?? 0
            _ = await syncNow()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 账号是否已过期
    var isAccountExpired: Bool {
        let e = accountExpires
        return e > 0 && e < Date().timeIntervalSince1970
    }

    func saveSync(_ c: SyncConfig) {
        syncConfig = c
        SharedStore.syncConfig = c
    }

    /// 从网页后台拉线路；远端线路覆盖，手动添加的保留
    @discardableResult
    func syncNow() async -> Bool {
        guard syncConfig.isConfigured else {
            syncConfig.lastMessage = "还没配置后台地址或未登录"
            saveSync(syncConfig)
            return false
        }
        if syncing { return false }
        syncing = true
        defer { syncing = false }

        do {
            let remote = try await SyncService.fetchNodes(base: syncConfig.baseURL, token: syncConfig.token)
            let incoming = SyncService.toServers(remote)
            let manual = servers.filter { !$0.isRemote }
            // 云端返回空时不要清空本地，避免一次异常把线路列表洗掉
            if incoming.isEmpty && !manual.isEmpty {
                syncConfig.lastMessage = "云端暂无线路，已保留本地列表"
                saveSync(syncConfig)
                return false
            }
            let merged = manual + incoming
            servers = merged
            if selectedID == nil || !merged.contains(where: { $0.id == selectedID }) {
                selectedID = merged.first?.id
            }
            persistServers()
            syncConfig.lastSync = Date().timeIntervalSince1970
            syncConfig.lastMessage = "已同步 \(incoming.count) 条云端线路"
            saveSync(syncConfig)
            return true
        } catch {
            syncConfig.lastMessage = "同步失败：\(error.localizedDescription)"
            saveSync(syncConfig)
            return false
        }
    }

    /// 把 NEVPNErrorDomain 的错误码翻译成人话
    nonisolated static func explain(_ error: Error) -> String {        let ns = error as NSError
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
