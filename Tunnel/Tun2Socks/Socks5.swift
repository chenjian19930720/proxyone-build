import Foundation

enum Socks5Error: Error, CustomStringConvertible {
    case socketFailed(String)
    case connectFailed(String)
    case handshake(String)

    var description: String {
        switch self {
        case .socketFailed(let s): return "socket 失败: \(s)"
        case .connectFailed(let s): return "连接失败: \(s)"
        case .handshake(let s): return "SOCKS5 握手失败: \(s)"
        }
    }
}

enum Socks5 {

    // MARK: 建立到目标地址的 TCP 隧道
    /// 返回已连接并完成 CONNECT 的 socket fd（阻塞模式）
    static func openTCP(server: ProxyServer,
                        dstHost: String,
                        dstPort: UInt16,
                        timeout: TimeInterval = 8) throws -> Int32 {
        let fd = try dialProxy(server: server, timeout: timeout)
        do {
            // SOCKS5 认证
            try negotiate(fd: fd, server: server)
            // CONNECT
            try sendRequest(fd: fd, cmd: 0x01, host: dstHost, port: dstPort)
            let (rep, _, _) = try readReply(fd: fd)
            guard rep == 0x00 else {
                close(fd)
                throw Socks5Error.handshake("CONNECT 被拒绝，REP=\(rep)（\(replyText(rep))）")
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    // MARK: 建立 UDP ASSOCIATE，返回 (控制连接 fd, 中继 IPv4 地址, 中继端口)
    static func openUDP(server: ProxyServer,
                        timeout: TimeInterval = 8) throws -> (fd: Int32, relayHost: String, relayPort: UInt16) {
        let fd = try dialProxy(server: server, timeout: timeout)
        do {
            try negotiate(fd: fd, server: server)
            // UDP ASSOCIATE，DST.ADDR/PORT 填 0.0.0.0:0
            try sendRequest(fd: fd, cmd: 0x03, host: "0.0.0.0", port: 0)
            let (rep, atyp, addrBytes) = try readReply(fd: fd)
            guard rep == 0x00 else {
                close(fd)
                throw Socks5Error.handshake("UDP ASSOCIATE 被拒绝，REP=\(rep)（\(replyText(rep))）")
            }
            var relayHost = "0.0.0.0"
            if atyp == 0x01, addrBytes.count >= 4 {
                var a: UInt32 = 0
                withUnsafeMutableBytes(of: &a) { $0.copyBytes(from: addrBytes[0..<4]) }
                relayHost = IPUtil.addrToString(a)
            } else if atyp == 0x03, !addrBytes.isEmpty {
                relayHost = String(bytes: addrBytes.dropFirst(), encoding: .utf8) ?? "0.0.0.0"
            }
            let port = UInt16(addrBytes[addrBytes.count - 2]) << 8 | UInt16(addrBytes[addrBytes.count - 1])
            if relayHost == "0.0.0.0" || port == 0 {
                relayHost = server.host
            }
            return (fd, relayHost, port)
        } catch {
            close(fd)
            throw error
        }
    }

    // MARK: - 内部步骤

    private static func dialProxy(server: ProxyServer, timeout: TimeInterval) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(server.host, String(server.port), &hints, &res)
        guard rc == 0, let info = res else {
            throw Socks5Error.connectFailed("无法解析 \(server.host)")
        }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw Socks5Error.socketFailed(String(cString: strerror(errno))) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
            let msg = String(cString: strerror(errno))
            close(fd)
            throw Socks5Error.connectFailed("\(server.endpoint) — \(msg)")
        }
        return fd
    }

    private static func negotiate(fd: Int32, server: ProxyServer) throws {
        let useAuth = !server.username.isEmpty
        var greeting: [UInt8] = [0x05]
        if useAuth {
            greeting.append(contentsOf: [0x02, 0x00, 0x02])
        } else {
            greeting.append(contentsOf: [0x01, 0x00])
        }
        try writeAll(fd, greeting)

        let resp = try readExactly(fd, 2)
        guard resp[0] == 0x05 else { throw Socks5Error.handshake("服务器不是 SOCKS5（版本 \(resp[0])）") }
        switch resp[1] {
        case 0x00:
            return
        case 0x02:
            let u = Array(server.username.utf8)
            let p = Array(server.password.utf8)
            guard u.count < 256, p.count < 256 else { throw Socks5Error.handshake("用户名或密码过长") }
            var auth: [UInt8] = [0x01, UInt8(u.count)]
            auth.append(contentsOf: u)
            auth.append(UInt8(p.count))
            auth.append(contentsOf: p)
            try writeAll(fd, auth)
            let r = try readExactly(fd, 2)
            guard r[1] == 0x00 else { throw Socks5Error.handshake("账号或密码错误") }
        case 0xFF:
            throw Socks5Error.handshake("服务器不接受任何认证方式")
        default:
            throw Socks5Error.handshake("未知认证方法 \(resp[1])")
        }
    }

    private static func sendRequest(fd: Int32, cmd: UInt8, host: String, port: UInt16) throws {
        var req: [UInt8] = [0x05, cmd, 0x00]
        if let ip = IPUtil.stringToAddr(host) {
            req.append(0x01)
            withUnsafeBytes(of: ip) { req.append(contentsOf: $0) }
        } else {
            let bytes = Array(host.utf8)
            guard bytes.count <= 255 else { throw Socks5Error.handshake("域名过长") }
            req.append(0x03)
            req.append(UInt8(bytes.count))
            req.append(contentsOf: bytes)
        }
        req.append(UInt8(port >> 8))
        req.append(UInt8(port & 0xFF))
        try writeAll(fd, req)
    }

    /// 返回 (REP, ATYP, 剩余地址+端口字节)
    private static func readReply(fd: Int32) throws -> (UInt8, UInt8, [UInt8]) {
        let head = try readExactly(fd, 4)
        guard head[0] == 0x05 else { throw Socks5Error.handshake("回复版本异常") }
        let rep = head[1]
        let atyp = head[3]
        var addr: [UInt8] = []
        switch atyp {
        case 0x01:
            addr = try readExactly(fd, 4 + 2)
        case 0x04:
            addr = try readExactly(fd, 16 + 2)
        case 0x03:
            let len = try readExactly(fd, 1)
            addr = [len[0]] + (try readExactly(fd, Int(len[0]) + 2))
        default:
            throw Socks5Error.handshake("未知地址类型 \(atyp)")
        }
        return (rep, atyp, addr)
    }

    private static func replyText(_ rep: UInt8) -> String {
        switch rep {
        case 1: return "一般性失败"
        case 2: return "规则不允许"
        case 3: return "网络不可达"
        case 4: return "主机不可达"
        case 5: return "连接被拒绝"
        case 6: return "TTL 过期"
        case 7: return "不支持的命令"
        case 8: return "不支持的地址类型"
        default: return "未知"
        }
    }

    // MARK: - IO 辅助
    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, bytes.count - sent) }
            if n <= 0 {
                if errno == EINTR { continue }
                throw Socks5Error.socketFailed("写失败 errno=\(errno)")
            }
            sent += n
        }
    }

    static func readExactly(_ fd: Int32, _ count: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: got), count - got) }
            if n <= 0 {
                if errno == EINTR { continue }
                throw Socks5Error.socketFailed("读失败 errno=\(errno)")
            }
            got += n
        }
        return buf
    }
}
