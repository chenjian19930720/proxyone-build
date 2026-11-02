import Foundation

/// 商业版内置配置。上线前把 defaultBackend 改成你自己的域名。
enum AppConfig {
    /// App 内置的服务器地址：用户不需要填，也看不到输入框。
    /// 上线时改成你的域名，例如 "https://ip.example.com"
    static let defaultBackend = "http://192.168.3.2:8787"

    /// 内置地址是否已经配置好
    static var hasBuiltinBackend: Bool {
        !defaultBackend.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 离线模式的访问密码。只有知道这个密码的人才能进离线版。
    /// 上线前改成你自己的密码；留空表示不校验（不建议）。
    static let offlinePassword = "cx2024"

    /// 离线密码是否启用
    static var offlineLockEnabled: Bool { !offlinePassword.isEmpty }

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
