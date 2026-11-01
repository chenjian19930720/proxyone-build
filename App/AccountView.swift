import SwiftUI
import UIKit

extension Notification.Name {
    static let proxyOneLogout = Notification.Name("proxyone.logout")
}

struct AccountView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var showSync = false
    @State private var showDebug = false
    @State private var shareURL: URL?
    @State private var showSSIDPrompt = false
    @State private var ssidInput = ""
    @State private var confirmLogout = false

    private var account: String {
        let n = SharedStore.accountName
        return n.isEmpty ? "本地用户" : n
    }

    private var isCloud: Bool { tunnel.syncConfig.isConfigured }
    private var cloudCount: Int { tunnel.servers.filter { $0.isRemote }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        profileCard
                        privilegeCard
                        toolsCard
                        aboutCard
                        logoutButton
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("账户管理")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSync) { SyncView() }
            .sheet(isPresented: $showDebug) { DebugView() }
            .sheet(item: Binding(
                get: { shareURL.map(ShareItem.init) },
                set: { if $0 == nil { shareURL = nil } }
            )) { item in
                ActivityView(url: item.url)
            }
            .alert("退出登录", isPresented: $confirmLogout) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { logout() }
            } message: {
                Text("退出后需要重新输入账号密码，已同步的线路会保留。")
            }
            .alert("导出 Wi-Fi 代理描述文件", isPresented: $showSSIDPrompt) {
                TextField("当前 Wi-Fi 名称（SSID）", text: $ssidInput)
                Button("取消", role: .cancel) {}
                Button("导出") {
                    guard let s = tunnel.currentServer, !ssidInput.isEmpty else { return }
                    let data = MobileConfigBuilder.make(ssid: ssidInput, proxyHost: s.host, proxyPort: s.port)
                    shareURL = MobileConfigBuilder.writeTemporaryFile(data: data)
                }
            } message: {
                Text("仅对该 Wi-Fi 生效，且地址必须是 HTTP 代理。")
            }
        }
    }

    // MARK: 账户卡
    private var profileCard: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(Theme.gradient)
                    .frame(width: 62, height: 62)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 14)
                Text(String(account.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(account)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(isCloud ? "云端账号" : "本地账号")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(isCloud ? Theme.ok : .white.opacity(0.5))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((isCloud ? Theme.ok : Color.white).opacity(0.14)))

                    if isCloud {
                        Text("已同步 \(cloudCount) 条")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }

                if isCloud {
                    Text(tunnel.syncConfig.baseURL)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .card()
    }

    // MARK: 权限 / 权益
    private var privilegeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("权限与权益")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            privilege(icon: "checkmark.seal.fill", color: Theme.ok,
                      title: "全局代理", detail: "TCP / UDP / DNS 全量转发", enabled: true)
            privilege(icon: "arrow.triangle.2.circlepath", color: isCloud ? Theme.ok : .white.opacity(0.3),
                      title: "云端线路同步", detail: isCloud ? "已连接 · \(cloudCount) 条线路" : "未连接网页后台",
                      enabled: isCloud)
            privilege(icon: "shield.lefthalf.filled", color: tunnel.alwaysOn ? Theme.ok : .white.opacity(0.3),
                      title: "强制保持连接", detail: tunnel.alwaysOn ? "已开启 · 断网自动重连" : "未开启",
                      enabled: tunnel.alwaysOn)
            privilege(icon: "lock.shield", color: .white.opacity(0.3),
                      title: "Shadowsocks / SSR", detail: "协议内核开发中，暂未开通", enabled: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func privilege(icon: String, color: Color, title: String, detail: String, enabled: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(enabled ? 0.9 : 0.45))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.28))
            }
            Spacer()
            Text(enabled ? "已开通" : "未开通")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(enabled ? Theme.ok : .white.opacity(0.25))
        }
    }

    // MARK: 工具
    private var toolsCard: some View {
        VStack(spacing: 0) {
            toolRow(icon: "arrow.triangle.2.circlepath", title: "线路同步") { showSync = true }
            divider
            toolRow(icon: "ladybug", title: "调试与日志") { showDebug = true }
            divider
            toolRow(icon: "wifi", title: "导出 Wi-Fi 代理描述文件") { showSSIDPrompt = true }
            divider
            toolRow(icon: "trash", title: "清空隧道日志") { TunnelLog.clear() }
        }
        .card(padding: 0, radius: 18)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 46)
    }

    private func toolRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.16))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: 关于
    private var aboutCard: some View {
        VStack(spacing: 9) {
            info("版本", "1.0 (build 5)")
            info("登录模式", isCloud ? "云端账号" : "本地模式")
            info("线路总数", "\(tunnel.servers.count)")
            info("扩展 ID", TunnelManager.tunnelBundleID)
            info("App Group", SharedStore.appGroup)
        }
        .card()
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(v)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var logoutButton: some View {
        Button {
            confirmLogout = true
        } label: {
            Text("退出登录")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.bad)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 15).fill(Theme.bad.opacity(0.12)))
        }
        .padding(.top, 4)
    }

    private func logout() {
        SharedStore.isLoggedIn = false
        SharedStore.accountName = ""
        var c = tunnel.syncConfig
        c.token = ""
        c.password = ""
        tunnel.saveSync(c)
        NotificationCenter.default.post(name: .proxyOneLogout, object: nil)
    }
}
