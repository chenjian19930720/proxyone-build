import Foundation

/// 商业版内置配置。上线前把 defaultBackend 改成你自己的域名。
enum AppConfig {
    /// App 内置的服务器地址：用户不需要填，也看不到输入框。
    /// 上线时改成你的域名，例如 "https://ip.example.com"
    static let defaultBackend = "http://42.194.237.113:8787"

    /// 内置地址是否已经配置好
    static var hasBuiltinBackend: Bool {
        !defaultBackend.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// App 自身版本（和后台设置里的「最新版本」比对，低于就提示更新）
    static let appVersion = "1.0"

    /// 离线模式的访问密码。只有知道这个密码的人才能进离线版。
    /// 服务器连不上时用它兜底；正常情况会用服务器下发的密码。
    static let offlinePassword = "chenjian520"

    /// 兜底密码的 sha256（服务器不可用时校验用）
    static let offlinePasswordHash = "9fd9a6bda7a1d9a447217e1413d993f652a1df5bed76ead7d2759505679c5e34"

    /// 离线密码是否启用
    static var offlineLockEnabled: Bool { true }

    /// 展示用的服务器标识（去掉 http:// 和端口）
    static var backendLabel: String {
        var s = defaultBackend
        for p in ["http://", "https://"] where s.hasPrefix(p) {
            s.removeFirst(p.count)
        }
        if let i = s.firstIndex(of: "/") { s = String(s[..<i]) }
        return s
    }
}
