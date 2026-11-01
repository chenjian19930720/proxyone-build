import Foundation

/// 备用方案：生成 .mobileconfig 描述文件，为指定 Wi-Fi 配置 HTTP/HTTPS 代理。
/// 不需要 Network Extension 权限（无需付费开发者账号也能装），
/// 但只对 Wi-Fi 生效，且仅支持 HTTP CONNECT 型代理。
enum MobileConfigBuilder {

    static func make(ssid: String,
                     proxyHost: String,
                     proxyPort: UInt16,
                     payloadName: String = "ProxyOne Wi-Fi 代理") -> Data {
        let uuid = UUID().uuidString
        let dict: [String: Any] = [
            "PayloadContent": [
                [
                    "PayloadType": "com.apple.wifi.managed",
                    "PayloadVersion": 1,
                    "PayloadIdentifier": "com.example.proxyone.wifi.\(uuid)",
                    "PayloadUUID": uuid,
                    "PayloadDisplayName": payloadName,
                    "SSID_STR": ssid,
                    "EncryptionType": "Any",
                    "ProxyType": "Manual",
                    "ProxyServer": proxyHost,
                    "ProxyServerPort": Int(proxyPort),
                    "ProxyCaptiveLoginAllowed": false
                ]
            ],
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "com.example.proxyone.profile.\(UUID().uuidString)",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": payloadName,
            "PayloadOrganization": "ProxyOne",
            "PayloadDescription": "为 Wi-Fi「\(ssid)」设置 HTTP 代理 \(proxyHost):\(proxyPort)",
            "PayloadRemovalDisallowed": false
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    static func writeTemporaryFile(data: Data, name: String = "proxyone.mobileconfig") -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
