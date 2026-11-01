import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var autoConnect = SharedStore.autoConnect
    @State private var showSSIDPrompt = false
    @State private var ssidInput = ""
    @State private var shareURL: URL?
    @State private var showDebug = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                List {
                    Section {
                        Toggle(isOn: $autoConnect) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自动连接")
                                    .font(.system(size: 14))
                                Text("App 启动时若已配置节点则自动连上")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                        }
                        .tint(Theme.accent)
                        .onChange(of: autoConnect) { v in
                            SharedStore.autoConnect = v
                        }
                    } header: {
                        sectionHeader("连接")
                    }

                    Section {
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
                        infoRow("版本", "1.0 (build 2)")
                        infoRow("扩展 Bundle ID", TunnelManager.tunnelBundleID)
                        infoRow("App Group", SharedStore.appGroup)
                        infoRow("线路数量", "\(tunnel.servers.count)")
                    } header: {
                        sectionHeader("关于")
                    } footer: {
                        Text("全局模式：TCP / UDP(含 DNS) 全部经 SOCKS5 线路转发。断线排查请先看「调试与日志」。")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.25))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDebug) { DebugView() }
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
