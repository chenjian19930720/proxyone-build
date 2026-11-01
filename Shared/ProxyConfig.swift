import Foundation

// MARK: - 模型

struct ProxyServer: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var password: String
    var remark: String
    var group: String
    var latency: Int?

    init(id: UUID = UUID(),
         name: String = "新线路",
         host: String = "",
         port: UInt16 = 1080,
         username: String = "",
         password: String = "",
         remark: String = "",
         group: String = "",
         latency: Int? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.remark = remark
        self.group = group
        self.latency = latency
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, password, remark, group, latency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "线路"
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? 1080
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        remark = try c.decodeIfPresent(String.self, forKey: .remark) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        latency = try c.decodeIfPresent(Int.self, forKey: .latency)
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0
    }

    var endpoint: String { "\(host):\(port)" }

    var displayGroup: String { group.isEmpty ? "我的线路" : group }

    /// 延迟档位：0 极快 1 良好 2 一般 3 慢 -1 未知
    var latencyLevel: Int {
        guard let ms = latency else { return -1 }
        if ms < 120 { return 0 }
        if ms < 250 { return 1 }
        if ms < 500 { return 2 }
        return 3
    }
}

// MARK: - App Group 共享存储

enum SharedStore {
    static let appGroup = "group.com.example.proxyone"
    private static let serversKey = "servers.v2"
    private static let selectedKey = "selected.server.v1"
    private static let autoConnectKey = "auto.connect.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func loadServers() -> [ProxyServer] {
        guard let data = defaults.data(forKey: serversKey),
              let list = try? JSONDecoder().decode([ProxyServer].self, from: data)
        else { return [] }
        return list
    }

    static func saveServers(_ servers: [ProxyServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: serversKey)
    }

    static var selectedServerID: UUID? {
        get { defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: selectedKey) }
    }

    static var autoConnect: Bool {
        get { defaults.bool(forKey: autoConnectKey) }
        set { defaults.set(newValue, forKey: autoConnectKey) }
    }

    /// 强制保持连接（on-demand）
    static var alwaysOn: Bool {
        get { defaults.bool(forKey: "always.on.v1") }
        set { defaults.set(newValue, forKey: "always.on.v1") }
    }

    static func selectedServer() -> ProxyServer? {
        let all = loadServers()
        if let id = selectedServerID, let s = all.first(where: { $0.id == id }) { return s }
        return all.first
    }

    static func encodeForProvider(_ server: ProxyServer) -> [String: Any] {
        let data = (try? JSONEncoder().encode(server)) ?? Data()
        return ["serverJSON": String(data: data, encoding: .utf8) ?? "{}"]
    }

    static func decodeFromProvider(_ dict: [String: Any]?) -> ProxyServer? {
        guard let json = dict?["serverJSON"] as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProxyServer.self, from: data)
    }
}

// MARK: - 批量导入解析

enum NodeImport {

    /// 支持这些写法（一行一条）：
    ///   socks5://user:pass@1.2.3.4:1080
    ///   1.2.3.4:1080
    ///   1.2.3.4:1080:user:pass
    ///   香港01|1.2.3.4|1080|user|pass
    ///   香港01 1.2.3.4 1080
    static func parse(_ text: String) -> [ProxyServer] {
        var out: [ProxyServer] = []
        let lines = text.components(separatedBy: CharacterSet.newlines)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            if let node = parseLine(line) { out.append(node) }
        }
        return out
    }

    private static func parseLine(_ line: String) -> ProxyServer? {
        var s = line

        // socks5://user:pass@host:port  →  去掉 scheme
        if let r = s.range(of: "://") {
            s = String(s[r.upperBound...])
        }

        // name|host|port|user|pass
        if s.contains("|") {
            let p = s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 3, let port = UInt16(p[2]) else { return nil }
            return ProxyServer(name: p[0].isEmpty ? p[1] : p[0],
                               host: p[1],
                               port: port,
                               username: p.count > 3 ? p[3] : "",
                               password: p.count > 4 ? p[4] : "",
                               group: "导入")
        }

        // user:pass@host:port
        if let at = s.lastIndex(of: "@") {
            let cred = String(s[s.startIndex..<at])
            let hostPart = String(s[s.index(after: at)...])
            let credParts = cred.components(separatedBy: ":")
            if let (host, port) = splitHostPort(hostPart) {
                return ProxyServer(name: host,
                                   host: host,
                                   port: port,
                                   username: credParts.first ?? "",
                                   password: credParts.count > 1 ? credParts[1] : "",
                                   group: "导入")
            }
        }

        // name host port
        let tokens = s.split(separator: " ").map(String.init)
        if tokens.count == 3, let port = UInt16(tokens[2]) {
            return ProxyServer(name: tokens[0], host: tokens[1], port: port, group: "导入")
        }

        // host:port:user:pass 或 host:port
        let parts = s.components(separatedBy: ":")
        if parts.count >= 2, let port = UInt16(parts[1]) {
            return ProxyServer(name: parts[0],
                               host: parts[0],
                               port: port,
                               username: parts.count > 2 ? parts[2] : "",
                               password: parts.count > 3 ? parts[3] : "",
                               group: "导入")
        }
        return nil
    }

    private static func splitHostPort(_ s: String) -> (String, UInt16)? {
        let parts = s.components(separatedBy: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), !parts[0].isEmpty else { return nil }
        return (parts[0], port)
    }
}

// MARK: - 日志

enum TunnelLog {
    private static let fileURL: URL = {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("tunnel.log")
    }()

    private static let lock = NSLock()
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ msg: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "[\(fmt.string(from: Date()))] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
        NSLog("[ProxyOne] %@", msg)
    }

    static func read() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "(空)"
    }

    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
