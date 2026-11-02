import Foundation

/// 极简 HTTP/1.1 客户端（基于 BSD socket）。
/// 目的：绕开 iOS 26 对 URLSession 明文 HTTP 的 ATS 拦截。
/// 只支持 http://，够我们用（后台是 http://IP:8787）。
enum SimpleHTTP {

    struct Response {
        let status: Int
        let body: Data
    }

    enum HTTPError: LocalizedError {
        case badURL
        case socket(String)
        case connect(String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "地址格式不对"
            case .socket(let s): return "socket 失败：\(s)"
            case .connect(let s): return "连接失败：\(s)"
            case .badResponse(let s): return "响应异常：\(s)"
            }
        }
    }

    // MARK: 从 URL 字符串解析
    struct Endpoint {
        let host: String
        let port: UInt16
        let path: String
    }

    static func endpoint(_ urlString: String) -> Endpoint? {
        var s = urlString.trimmingCharacters(in: .whitespaces)
        guard s.lowercased().hasPrefix("http://") else { return nil }
        s.removeFirst(7)
        var hostPart = s
        var path = "/"
        if let slash = s.firstIndex(of: "/") {
            hostPart = String(s[..<slash])
            path = String(s[slash...])
        }
        var host = hostPart
        var port: UInt16 = 80
        if let colon = hostPart.lastIndex(of: ":"),
           let p = UInt16(hostPart[hostPart.index(after: colon)...]) {
            host = String(hostPart[..<colon])
            port = p
        }
        guard !host.isEmpty else { return nil }
        return Endpoint(host: host, port: port, path: path)
    }

    // MARK: 请求
    static func request(_ urlString: String,
                        method: String = "GET",
                        jsonBody: [String: Any]? = nil,
                        token: String? = nil,
                        timeout: TimeInterval = 12) throws -> Response {

        guard let ep = endpoint(urlString) else { throw HTTPError.badURL }

        // 解析 host（支持域名）
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ep.host, String(ep.port), &hints, &res) == 0, let info = res else {
            throw HTTPError.connect("DNS 解析失败 \(ep.host)")
        }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw HTTPError.socket(String(cString: strerror(errno))) }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        guard SocketUtil.connectWithTimeout(fd: fd,
                                            addr: info.pointee.ai_addr,
                                            len: info.pointee.ai_addrlen,
                                            timeoutMs: Int32(timeout * 1000)) else {
            throw HTTPError.connect("\(ep.host):\(ep.port) 连接超时或不可达")
        }

        // 构造请求
        var bodyData = Data()
        if let json = jsonBody,
           let d = try? JSONSerialization.data(withJSONObject: json) {
            bodyData = d
        }
        var req = "\(method) \(ep.path) HTTP/1.1\r\n"
        req += "Host: \(ep.host):\(ep.port)\r\n"
        req += "User-Agent: DaixuIP/1.0\r\n"
        req += "Accept: application/json\r\n"
        req += "Connection: close\r\n"
        if let token, !token.isEmpty {
            req += "Authorization: Bearer \(token)\r\n"
        }
        if !bodyData.isEmpty {
            req += "Content-Type: application/json\r\n"
            req += "Content-Length: \(bodyData.count)\r\n"
        }
        req += "\r\n"

        var payload = Array(req.utf8)
        payload.append(contentsOf: bodyData)

        var sent = 0
        while sent < payload.count {
            let n = payload[sent...].withUnsafeBytes {
                write(fd, $0.baseAddress, payload.count - sent)
            }
            if n > 0 { sent += n; continue }
            if errno == EINTR { continue }
            throw HTTPError.socket("写失败 errno=\(errno)")
        }

        // 读响应
        var raw = Data()
        let cap = 8 * 1024 * 1024
        while raw.count < cap {
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, 8192) }
            if n > 0 {
                raw.append(contentsOf: buf[0..<n])
                continue
            }
            if n == 0 { break }
            if errno == EINTR { continue }
            break
        }

        guard let sep = raw.range(of: Data("\r\n\r\n".utf8)) else {
            throw HTTPError.badResponse("没有响应头（收到 \(raw.count) 字节）")
        }
        let headerStr = String(data: raw[..<sep.lowerBound], encoding: .utf8) ?? ""
        var body = Data(raw[sep.upperBound...])

        let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else {
            throw HTTPError.badResponse("状态行异常：\(firstLine)")
        }

        // 按 Content-Length 截断
        for line in headerStr.components(separatedBy: "\r\n") {
            let low = line.lowercased()
            if low.hasPrefix("content-length:") {
                let v = line.components(separatedBy: ":").last?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if let len = Int(v), body.count > len {
                    body = body.prefix(len)
                }
                break
            }
        }

        return Response(status: status, body: body)
    }

    // MARK: 便捷方法
    static func getJSON(_ url: String, token: String? = nil) throws -> [String: Any] {
        let r = try request(url, token: token)
        guard r.status == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: r.body) as? [String: Any])?["error"] as? String
            throw HTTPError.badResponse("HTTP \(r.status) \(msg ?? "")")
        }
        return (try? JSONSerialization.jsonObject(with: r.body) as? [String: Any]) ?? [:]
    }

    static func postJSON(_ url: String, body: [String: Any], token: String? = nil,
                         allowStatus: Set<Int> = [200]) throws -> (Int, [String: Any]) {
        let r = try request(url, method: "POST", jsonBody: body, token: token)
        let obj = (try? JSONSerialization.jsonObject(with: r.body) as? [String: Any]) ?? [:]
        if !allowStatus.contains(r.status) {
            let msg = obj["error"] as? String ?? "HTTP \(r.status)"
            throw HTTPError.badResponse(msg)
        }
        return (r.status, obj)
    }
}
