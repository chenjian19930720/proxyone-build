# ProxyOne · iOS 一键全局代理（SOCKS5）

一个可以直接编译运行的 iOS App：点一下开关，整台手机的 **TCP + UDP（含 DNS）** 全部走你自己的 SOCKS5 服务器。
不是"设置里手动填代理"，而是真正接管流量的 **Network Extension Packet Tunnel**（和 Shadowrocket / Surge 同一套机制）。

```
┌─────────────┐   utun (10.7.0.2)   ┌──────────────────────┐   SOCKS5    ┌──────────┐
│ 系统 / 各 App │ ──────────────────▶ │ PacketTunnelProvider │ ──────────▶ │ 你的服务器 │ ──▶ Internet
└─────────────┘   IPv4 全部流量       │  Tun2Socks 引擎       │  TCP/UDP    └──────────┘
                                      └──────────────────────┘
```

## 目录

```
ProxyOne/
├── ProxyOne.xcodeproj/             # 已生成好的工程（含共享 scheme），双击即可打开
├── build-ipa.sh                    # Mac 上一键出未签名 ipa
├── .github/workflows/build.yml     # 没 Mac 时用 GitHub Actions 出 ipa
├── SIGNING.md                      # 自签要求 / entitlements / 两个 Bundle ID 怎么配
├── project.yml                     # 可选：XcodeGen 描述（改文件清单时用）
├── App/                            # 主 App（SwiftUI）
│   ├── ProxyOneApp.swift
│   ├── ContentView.swift           # 大按钮 + 节点列表 + 日志 + 导出描述文件
│   ├── ServerEditorView.swift
│   └── TunnelManager.swift         # NETunnelProviderManager 管理、一键开关、测延迟
├── Shared/
│   ├── ProxyConfig.swift           # 配置模型 + App Group + 日志
│   └── MobileConfig.swift          # 备用方案：导出 Wi-Fi HTTP 代理描述文件
├── Tunnel/                         # 扩展（真正干活的地方）
│   ├── PacketTunnelProvider.swift  # 建隧道、设路由、排除服务器 IP
│   └── Tun2Socks/
│       ├── Tun2Socks.swift         # 收包分发 / 发包 / 定时维护
│       ├── IPPacket.swift          # IPv4/TCP/UDP 解析与构造、校验和
│       ├── Socks5.swift            # SOCKS5 握手、CONNECT、UDP ASSOCIATE
│       ├── TCPRelay.swift          # 一条 TCP 流的状态机
│       ├── UDPRelay.swift          # UDP over SOCKS5（DNS 靠它）
│       └── DNSRelay.swift          # 服务器不支持 UDP 时，DNS 走 TCP 兜底
├── tools/                          # 工程自检 + 云端构建脚本
├── Resources/                      # App Info.plist + entitlements
└── Tunnel/Resources/               # 扩展 Info.plist + entitlements
```

## 拿到 ipa 的三条路

工程里已经带好 `ProxyOne.xcodeproj`（手写 pbxproj，已校验），**不需要 XcodeGen**，直接打开就能编。

### 路 A：有 Mac（最快）

```bash
bash build-ipa.sh
# 产出 ProxyOne-unsigned.ipa
```

脚本用 `xcodebuild -sdk iphoneos ARCHS=arm64 CODE_SIGNING_ALLOWED=NO` 编译，再把 `.app` 装进 `Payload/` 打 zip，全程不签名。

### 路 B：没有 Mac，用 GitHub Actions 的 macOS runner

仓库里已带 `.github/workflows/build.yml`：

1. 把 `ProxyOne-source.zip` 解压后的内容推到你的 GitHub 仓库（`main` 分支）
2. 打开仓库 **Actions → build-ipa → Run workflow**
3. 跑完（约 3-5 分钟）在 run 页面底部下载 `ProxyOne-unsigned-ipa`

### 路 C：一条命令全自动（本机跑，用你的 token 调 GitHub API）

```powershell
$env:GH_TOKEN="ghp_xxxxxxxx"
python tools/cloud_build.py
```

它会：建私有仓库 → 上传全部源码 → 触发 macOS 构建 → 轮询状态 → 把 `ProxyOne-unsigned.ipa` 下载回当前目录。
token 用 classic PAT，勾 **repo + workflow** 两个 scope。

## 签名前必读

见 [SIGNING.md](SIGNING.md)。三个硬条件：

1. **付费 Apple Developer 账号**（$99/年）：`Network Extension` entitlement 不对免费证书开放；
2. 主 App 和扩展**两个 Bundle ID** 都要在你账号下注册，扩展 ID 以宿主 ID 开头；
3. 两个 App ID 都要开 **App Groups**，扩展还要开 **Network Extensions → Packet Tunnel**。

免费证书签出来的包能装、能开，但扩展不会启动，点开关没反应。

## 改 ID（必须）

| 位置 | 值 |
|---|---|
| `ProxyOne.xcodeproj` → Signing & Capabilities → Team | 你的 Team ID |
| `Shared/ProxyConfig.swift` → `SharedStore.appGroup` | 你的 App Group |
| `App/TunnelManager.swift` → `tunnelBundleID` | 你的扩展 bundle id |
| `project.yml`（只在用 XcodeGen 时） | `DEVELOPMENT_TEAM` / `bundleIdPrefix` |

两个 entitlements 文件里的 group 名要同步改。

## 工程自检工具

```bash
python tools/validate_project.py     # pbxproj 结构、UUID、源文件路径
python tools/swift_syntax_check.py   # 13 个 swift 文件语法解析
python tools/gen_xcodeproj.py        # 改了文件清单后重新生成 .xcodeproj
```

## 用起来

1. 打开 App → 右上角 `+` → 填 SOCKS5 地址、端口（有账号就填用户名密码）
2. 点中间的大圆按钮 → 首次弹「添加 VPN 配置」→ 允许
3. 状态变成 **已连接 · 全局代理生效** 就是全局生效了（状态栏会出现 VPN 图标）

验证：

```bash
# 手机浏览器访问，看到的应该已经是代理出口 IP
curl -s https://api.ipify.org          # 或在 Safari 打开 ip.sb
```

App 里点节点右边的 ⚡ 是直达服务器端口的 TCP 握手测速；左上角 📄 看扩展日志。

## 关键实现点

| 点 | 做法 |
|---|---|
| 全局拦截 | `NEIPv4Route.default()` 把 `0.0.0.0/0` 全部塞进隧道 |
| 防回环 | 把解析出的**代理服务器 IP** 加进 `excludedRoutes`（掩码 255.255.255.255），否则连服务器本身也会进隧道，直接死 |
| DNS | 隧道内指定 `1.1.1.1 / 8.8.8.8`，DNS 查询是 UDP，被 `UDPRelay` 用 SOCKS5 `UDP ASSOCIATE` 转发出去 |
| UDP | 每个本地 UDP 源端口一个独立 socket → 返回包能精确回注；服务器不支持 UDP ASSOCIATE 时 DNS 会不通，此时只能换支持 UDP 的服务端 |
| TCP | `TCPRelay` 负责 SYN/SYN-ACK、序号/ACK、FIN/RST，应用数据顺序写入 SOCKS socket |
| MTU | 1400（iOS 上偏保守，避免分片） |
| IPv6 | 不接管，走原生网络。要全量 IPv6 需要再写一套 IPv6 解析 + `NEIPv6Route` |

## 已知限制 / 想继续改的地方

- UDP 是"每源端口一个 socket"的简化实现，P2P / 大量 UDP 会话时 fd 会多，可换成端口池 + NAT 表。
- TCP 没做拥塞控制和重传定时器（utun 是内存管道基本不丢包，但公网抖动大时吞吐会掉）；要跑满带宽建议把 `TCPRelay` 换成 lwIP + `hev-socks5-tunnel` 的 C 实现。
- 没做分流（国内直连 / 域名规则），全部硬走代理。
- 没做订阅导入，节点是本地手填。
- 扩展内存上限 50MB 左右，日志文件要定期清（App 里能清）。

## 服务端准备（任选）

```bash
# 最省事：SSH 动态转发（只有 TCP，DNS 会走不通）
ssh -N -D 0.0.0.0:1080 user@your-server

# gost：同时支持 TCP + UDP ASSOCIATE
gost -L socks5://user:pass@:1080

# dante
socksmethod: username
user.privileged: root
```

装好后在 App 里填 `服务器IP` + `1080` 就能用。

## 备用方案（不需要 Network Extension）

App 左上角 ↥ 可以导出 `.mobileconfig`：给指定 Wi-Fi 配 HTTP 代理，安装后该 Wi-Fi 下流量走代理。
优点是不需要付费证书，缺点是只对 Wi-Fi 生效、只支持 HTTP 代理、需要用户手动装描述文件。

## 网页后台（线路管理 + App 同步）

`server/admin_server.py` 是零依赖单文件后台，自带网页管理界面。

```bash
python server/admin_server.py --port 8787 --user admin --pass admin888
# 浏览器打开 http://本机IP:8787
```

- 网页里增删线路、批量导入、停用/启用
- App「设置 → 线路同步」填同一个地址 + 账号密码 → 点「登录并同步」
- 之后后台每次改线路，App 打开时自动拉取（云端线路覆盖，手动添加的保留）

部署到公网服务器：

```bash
# 后台常驻
nohup python3 admin_server.py --port 8787 > admin.log 2>&1 &

# 或用 systemd（/etc/systemd/system/daixu.service）
[Service]
ExecStart=/usr/bin/python3 /opt/daixu/admin_server.py --port 8787 --user admin --pass 你的密码
Restart=always
```

数据存在同目录 `nodes.json`，密码校验用 HMAC，token 40 位，请求走 `Authorization: Bearer`。

API（也可以自己接别的客户端）：

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/login` | `{username,password}` → `{token}` |
| GET | `/api/nodes` | 需要 token，返回全部线路 |
| POST | `/api/nodes` | 新增/更新一条 |
| POST | `/api/nodes/delete` | 删除 |
| POST | `/api/nodes/bulk` | 文本批量导入 |
| GET | `/api/ping` | 健康检查 |

## 代理协议支持现状

| 协议 | 状态 |
|---|---|
| SOCKS5（含账号密码、UDP ASSOCIATE） | ✅ 完整支持，全局转发 |
| HTTP/HTTPS 代理 | ⚠️ 只能通过导出的 Wi-Fi 描述文件使用 |
| Shadowsocks (AEAD) / SSR | 🚧 协议内核在下一版实现（需要 ShadowStream 加密层 + SOCKS5 替身传输） |

## 部署到自己的公网服务器

后台是单文件、零依赖，只要能跑 Python 3 的机器就行。

### 1. 上传

```bash
scp ProxyOne/server/admin_server.py root@你的服务器:/opt/daixu/
```

### 2. 一键部署（systemd + 防火墙）

```bash
ssh root@你的服务器
cd /opt/daixu
sudo bash deploy.sh 8787
```

脚本会：建目录 → 生成签名密钥 → 装 systemd 服务 → 开机自启 → 放行端口。
完成时打印访问地址和管理员账号（默认 `admin` / `admin888`，**装完立刻改**）。

### 3. 配 HTTPS（强烈建议）

没有 HTTPS，用户密码是明文过公网的。用 Caddy 一行搞定：

```bash
# 假设域名 ip.example.com 已解析到这台服务器
sudo apt install -y caddy
sudo systemctl edit caddy     # 或直接改 /etc/caddy/Caddyfile
```

`/etc/caddy/Caddyfile`：

```
ip.example.com {
    encode gzip
    reverse_proxy 127.0.0.1:8787
}
```

```bash
sudo systemctl reload caddy
```

Caddy 会自动申请并续期 Let's Encrypt 证书。

### 4. 把 App 的地址指过去

```bash
python tools/set_backend.py https://ip.example.com     # 改内置地址
python tools/set_backend.py https://ip.example.com --build   # 改完顺便出包
```

改的是 `App/AppConfig.swift` 里一行，用户打开 App 就不用填地址了。

### 5. 数据与备份

```
/opt/daixu/users.json     账号（PBKDF2 密码 + 到期时间 + 审核状态）
/opt/daixu/nodes.json     线路
/opt/daixu/.secret        token 签名密钥（丢了所有用户都要重新登录）
```

```bash
# 每天 4 点自动备份，保留 30 份
crontab -e
0 4 * * * bash /opt/daixu/backup.sh >> /opt/daixu/backup.log 2>&1
```

### 6. 运营流程

1. 用户打开 App → 点「没有账号？申请开通」→ 提交账号密码
2. 你在后台「用户管理」看到黄色高亮的待审核记录（带明文密码和联系方式）
3. 点「开通」填天数 → 用户立刻能登录
4. 到期后自动拒绝登录；需要续费就点「续期」

### 安全清单

- [ ] 改掉默认管理员密码（`systemctl edit` 里的 `--pass` 参数）
- [ ] 配 HTTPS，别让密码走明文
- [ ] 8787 端口只对 Caddy 本机开放（防火墙别直接放公网）
- [ ] `users.json` / `nodes.json` / `.secret` 不要提交到任何仓库
- [ ] 定期备份 `.secret`，否则用户全部掉线
