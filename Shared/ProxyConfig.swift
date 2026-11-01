import Foundation

// MARK: - 模型

struct ProxyServer: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "默认节点"
    var host: String = ""
    var port: UInt16 = 1080
    var username: String = ""
    var password: String = ""
    var remark: String = ""

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0
    }

    var endpoint: String { "\(host):\(port)" }
}

// MARK: - App Group 共享存储

enum SharedStore {
    static let appGroup = "group.com.example.proxyone"
    private static let serversKey = "servers.v1"
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

// MARK: - 日志（App Group 共享，方便真机排查）

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
