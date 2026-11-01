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
}

struct RemoteNodeList: Codable {
    var nodes: [RemoteNode]?
    var updated: TimeInterval?
}

struct RemoteLoginResult: Codable {
    var token: String?
    var server: String?
    var error: String?
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

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        if s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    private static func post(_ url: URL, body: [String: Any], token: String?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw SyncError.http(code, msg ?? "请求失败")
            }
            return data
        } catch let e as SyncError {
            throw e
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
    }

    private static func get(_ url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw SyncError.http(code, msg ?? "请求失败")
            }
            return data
        } catch let e as SyncError {
            throw e
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
    }

    static func login(base: String, user: String, pass: String) async throws -> String {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.appendingPathComponent("api/login")
        let data = try await post(url, body: ["username": user, "password": pass], token: nil)
        let r = try? JSONDecoder().decode(RemoteLoginResult.self, from: data)
        guard let token = r?.token, !token.isEmpty else {
            throw SyncError.http(200, r?.error ?? "返回里没有 token")
        }
        return token
    }

    static func fetchNodes(base: String, token: String) async throws -> [RemoteNode] {
        guard let root = normalize(base) else { throw SyncError.badURL }
        let url = root.appendingPathComponent("api/nodes")
        let data = try await get(url, token: token)
        let list = try? JSONDecoder().decode(RemoteNodeList.self, from: data)
        return list?.nodes ?? []
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
                               isRemote: true)
        }
    }
}
