import Foundation

/// socket 工具：带硬超时的 connect。
/// 直接用阻塞 connect 时，SO_SNDTIMEO 不会生效，遇到不通的地址会卡到内核默认超时（约 75 秒）。
enum SocketUtil {

    /// 非阻塞 connect + poll，超时返回 false
    static func connectWithTimeout(fd: Int32,
                                   addr: UnsafePointer<sockaddr>,
                                   len: socklen_t,
                                   timeoutMs: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return false }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let rc = connect(fd, addr, len)
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pr = poll(&pfd, 1, timeoutMs)
        guard pr > 0 else { return false }

        var soErr: Int32 = 0
        var soLen = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &soLen) == 0 else { return false }
        guard soErr == 0 else { return false }

        // 恢复阻塞模式，后续按普通阻塞 socket 收发
        _ = fcntl(fd, F_SETFL, flags)
        return true
    }
}
