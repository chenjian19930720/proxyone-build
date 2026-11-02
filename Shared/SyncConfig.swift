import Foundation

// MARK: - 后台同步配置

struct SyncConfig: Codable {
    var baseURL: String = ""
    var username: String = ""
    var password: String = ""
    var token: String = ""
    var autoSync: Bool = true
    var lastSync: TimeInterval = 0
    var lastMessage: String = ""

    enum CodingKeys: String, CodingKey {
        case baseURL, username, password, token, autoSync, lastSync, lastMessage
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        autoSync = try c.decodeIfPresent(Bool.self, forKey: .autoSync) ?? true
        lastSync = try c.decodeIfPresent(TimeInterval.self, forKey: .lastSync) ?? 0
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? ""
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !token.isEmpty
    }
}

// MARK: - 远端节点

struct RemoteNode: Codable {
    var id: String?
    var name: String?
    var host: String?
    var port: Int?
    var username: String?
    var password: String?
    var group: String?
    var enabled: Bool?
    var proto: String?          // JSON 里叫 protocol，protocol 是保留字

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, password, group, enabled
        case proto = "protocol"
    }
}

struct RemoteNodeList: Codable {
    var nodes: [RemoteNode]?
    var updated: TimeInterval?
}

struct RemoteUserInfo: Codable {
    var username: String?
    var expires: TimeInterval?
    var group: String?
}

struct RemoteLoginResult: Codable {
    var token: String?
    var role: String?
    var user: RemoteUserInfo?
    var error: String?
}

struct RemoteMe: Codable {
    var username: String?
    var expires: TimeInterval?
    var enabled: Bool?
    var active: Bool?
    var reason: String?
    var group: String?
}

struct RemoteConfig: Codable {
    var offline_password_sha256: String?
    var announcement: String?
    var app_version: String?
    var app_update_url: String?
    var server: String?
    var version: String?
}

// MARK: - 同步服务

enum SyncError: LocalizedError {
    case badURL
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址格式不对，例如 http://1.2.3.4:8787"
        case .http(let code, let msg): return "HTTP \(code)：\(msg)"
        case .network(let msg): return "网络错误：\(msg)"
        }
    }
}

enum SyncService {

    /// 把阻塞的 socket 请求放到后台线程，保持 async 接口
    private static func run<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try block()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        if s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    static func login(base: String, user: String, pass: String) async throws -> (String, RemoteUserInfo?) {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.absoluteString + "/api/user/login"
        return try await run {
            let (_, obj) = try SimpleHTTP.postJSON(url,
                                                   body: ["username": user, "password": pass])
            guard let token = obj["token"] as? String, !token.isEmpty else {
                throw SyncError.http(200, (obj["error"] as? String) ?? "返回里没有 token")
            }
            var info: RemoteUserInfo?
            if let u = obj["user"] as? [String: Any] {
                info = RemoteUserInfo(username: u["username"] as? String,
                                      expires: (u["expires"] as? NSNumber)?.doubleValue,
                                      group: u["group"] as? String)
            }
            return (token, info)
        }
    }

    static func fetchNodes(base: String, token: String) async throws -> [RemoteNode] {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.absoluteString + "/api/nodes"
        return try await run {
            let obj = try SimpleHTTP.getJSON(url, token: token)
            let data = try JSONSerialization.data(withJSONObject: obj)
            let list = try? JSONDecoder().decode(RemoteNodeList.self, from: data)
            return list?.nodes ?? []
        }
    }

    static func fetchConfig(base: String) async throws -> RemoteConfig {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.absoluteString + "/api/config"
        return try await run {
            let obj = try SimpleHTTP.getJSON(url)
            let data = try JSONSerialization.data(withJSONObject: obj)
            return (try? JSONDecoder().decode(RemoteConfig.self, from: data)) ?? RemoteConfig()
        }
    }

    static func fetchMe(base: String, token: String) async throws -> RemoteMe {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.absoluteString + "/api/me"
        return try await run {
            let obj = try SimpleHTTP.getJSON(url, token: token)
            let data = try JSONSerialization.data(withJSONObject: obj)
            return (try? JSONDecoder().decode(RemoteMe.self, from: data)) ?? RemoteMe()
        }
    }

    static func register(base: String, user: String, pass: String, contact: String) async throws -> String {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.absoluteString + "/api/register"
        return try await run {
            let (_, obj) = try SimpleHTTP.postJSON(url,
                                                   body: ["username": user, "password": pass,
                                                          "contact": contact])
            return (obj["message"] as? String) ?? "提交成功，等待管理员开通"
        }
    }

    static func toServers(_ remote: [RemoteNode]) -> [ProxyServer] {
        remote.compactMap { r in
            guard let host = r.host, !host.isEmpty else { return nil }
            let port = UInt16(clamping: r.port ?? 0)
            guard port > 0 else { return nil }
            if r.enabled == false { return nil }
            return ProxyServer(name: r.name ?? host,
                               host: host,
                               port: port,
                               username: r.username ?? "",
                               password: r.password ?? "",
                               group: (r.group?.isEmpty == false ? r.group! : "云端"),
                               isRemote: true,
                               proto: (r.proto ?? "socks5").lowercased())
        }
    }
}
