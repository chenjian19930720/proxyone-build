import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var autoConnect = SharedStore.autoConnect
    @State private var sharedAutoConnect = SharedStore.autoConnect
    @State private var showSSIDPrompt = false
    @State private var ssidInput = ""
    @State private var shareURL: URL?
    @State private var showDebug = false
    @State private var showSync = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                List {
                    Section {
                        Toggle(isOn: Binding(
                            get: { tunnel.alwaysOn },
                            set: { v in Task { await tunnel.setAlwaysOn(v) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("强制保持连接")
                                    .font(.system(size: 14))
                                Text("系统级 on-demand：断网自动重连，有网立即连上，App 关掉也不断")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                        }
                        .tint(Theme.accent)

                        Toggle(isOn: Binding(
                            get: { sharedAutoConnect },
                            set: { v in
                                sharedAutoConnect = v
                                SharedStore.autoConnect = v
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("打开 App 自动连接")
                                    .font(.system(size: 14))
                                Text("启动时若有可用线路则自动发起连接")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                        }
                        .tint(Theme.accent)
                    } header: {
                        sectionHeader("连接")
                    }

                    Section {
                        Button {
                            showSync = true
                        } label: {
                            settingRow(icon: "arrow.triangle.2.circlepath",
                                       title: "线路同步（网页后台）",
                                       detail: tunnel.syncConfig.isConfigured
                                       ? "已连接 · \(tunnel.servers.filter { $0.isRemote }.count) 条云端线路"
                                       : "填后台地址和账号，自动同步线路")
                        }
                        Button {
                            showDebug = true
                        } label: {
                            settingRow(icon: "ladybug", title: "调试与日志", detail: "出口 IP / SOCKS5 诊断 / 隧道日志")
                        }
                        Button {
                            showSSIDPrompt = true
                        } label: {
                            settingRow(icon: "wifi", title: "导出 Wi-Fi 代理描述文件", detail: "HTTP 代理，不需要开发者证书")
                        }
                        Button {
                            TunnelLog.clear()
                        } label: {
                            settingRow(icon: "trash", title: "清空隧道日志", detail: nil)
                        }
                    } header: {
                        sectionHeader("工具")
                    }

                    Section {
                        infoRow("登录账号", SharedStore.accountName.isEmpty ? "本地模式" : SharedStore.accountName)
                        infoRow("版本", "1.0 (build 4)")
                        infoRow("扩展 Bundle ID", TunnelManager.tunnelBundleID)
                        infoRow("App Group", SharedStore.appGroup)
                        infoRow("线路数量", "\(tunnel.servers.count)（云端 \(tunnel.servers.filter { $0.isRemote }.count)）")
                    } header: {
                        sectionHeader("关于")
                    } footer: {
                        Text("全局模式：TCP / UDP(含 DNS) 全部经线路转发。断线排查请先看「调试与日志」。")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.25))
                    }

                    Section {
                        Button {
                            SharedStore.isLoggedIn = false
                            SharedStore.accountName = ""
                            var c = tunnel.syncConfig
                            c.token = ""
                            c.password = ""
                            tunnel.saveSync(c)
                        } label: {
                            Text("退出登录")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.bad)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDebug) { DebugView() }
            .sheet(isPresented: $showSync) { SyncView() }
            .sheet(item: Binding(
                get: { shareURL.map(ShareItem.init) },
                set: { if $0 == nil { shareURL = nil } }
            )) { item in
                ActivityView(url: item.url)
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
                Text("仅对该 Wi-Fi 生效，且地址必须是 HTTP 代理（不是 SOCKS5）。")
            }
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.45))
    }

    private func settingRow(icon: String, title: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.32))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.18))
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(v)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
