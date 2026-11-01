# 自己签名的注意事项

`ProxyOne-unsigned.ipa` 是**未签名**的，所以签名工具（Sideloadly / iOS App Signer / 企业分发平台）需要把下面这些 entitlement 重新装回去，否则 App 能装上但"一键连接"点了没反应。

## 一、两个 Bundle ID 必须都在你的账号下注册

| 目标 | 建议 Bundle ID | 必须开启的能力 |
|---|---|---|
| 主 App | `com.yourname.proxyone` | **App Groups**（`group.com.yourname.proxyone`） |
| 扩展 | `com.yourname.proxyone.tunnel` | **App Groups**（同上）+ **Network Extensions → Packet Tunnel** |

扩展的 Bundle ID 必须是主 App 的前缀 + `.tunnel`（Apple 要求扩展 ID 以宿主 ID 开头）。

`com.example.*` 是占位符，签名前要改成你自己账号下真实存在的 ID，同时改这三处：

- `App/TunnelManager.swift` → `tunnelBundleID`
- `Shared/ProxyConfig.swift` → `SharedStore.appGroup`
- 两个 entitlements 文件里的 group 名

（如果只是本地跑，也可以在 Xcode 里直接改 Signing & Capabilities，Xcode 会同步写回 entitlements。）

## 二、两个 entitlements 的最终内容

`ProxyOne.app`：
```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.yourname.proxyone</string></array>
```

`ProxyOne.app/PlugIns/ProxyOneTunnel.appex`：
```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.yourname.proxyone</string></array>
<key>com.apple.developer.networking.networkextension</key>
<array><string>packet-tunnel-provider</string></array>
```

## 三、Provisioning Profile

- 主 App 一份 profile，扩展**单独一份** profile（扩展有自己的 Bundle ID）。
- Sideloadly 会自动为 ipa 里每个可执行文件找匹配的 profile，所以要准备好两份（都包含对应 ID + 对应能力）。
- 企业证书（In-House）也要求 App ID 上勾了 Network Extensions，否则装完扩展加载失败，日志里是 `NEVPNErrorDomain error 1` 或"未配置"。

## 四、免费 Apple ID（7 天证书）的真实结果

免费个人签名**不支持** App Groups 和 Network Extension。表现：

1. App 能启动、界面正常；
2. 点"一键连接" → 系统不弹"添加 VPN 配置"，或弹了之后立刻断开；
3. 扩展进程根本不会启动（`Console.app` 里搜 `ProxyOneTunnel` 没有任何输出）。

要真正实现全局代理，签名证书必须是 **付费 Apple Developer Program（个人 $99/年 或 企业）**。

## 五、签完自检

```bash
# 1. 看扩展是否被正确签名（在 Mac 上对解压后的 .app 执行）
codesign -d --entitlements :- Payload/ProxyOne.app/PlugIns/ProxyOneTunnel.appex

# 2. 应该能看到 networkextension = packet-tunnel-provider
```

手机上：打开 App → 点大按钮 → 出现「ProxyOne 想要添加 VPN 配置」→ 允许 → 状态栏出现 VPN 图标 → Safari 打开 `ip.sb` 看出口 IP 是否已变。
