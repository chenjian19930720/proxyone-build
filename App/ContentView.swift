import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @State private var showEditor = false
    @State private var editing: ProxyServer?
    @State private var showLog = false
    @State private var pings: [UUID: Int] = [:]
    @State private var shareURL: URL?
    @State private var showSSIDPrompt = false
    @State private var ssidInput = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    powerButton
                    statusArea
                    serverSection
                    if let err = tunnel.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("ProxyOne")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button { showLog = true } label: {
                            Image(systemName: "ladybug")
                        }
                        Button { exportProfile() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editing = nil; showEditor = true } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                ServerEditorView(server: editing) { saved in
                    tunnel.upsert(saved)
                }
            }
            .sheet(isPresented: $showLog) { DebugView() }
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
                    let data = MobileConfigBuilder.make(ssid: ssidInput,
                                                        proxyHost: s.host,
                                                        proxyPort: s.port)
                    shareURL = MobileConfigBuilder.writeTemporaryFile(data: data)
                }
            } message: {
                Text("仅对填写的 Wi-Fi 生效，且该地址必须是 HTTP 代理（不是 SOCKS5）。")
            }
        }
    }

    private func exportProfile() {
        guard tunnel.currentServer != nil else { return }
        showSSIDPrompt = true
    }

    // MARK: - 大开关
    private var powerButton: some View {
        Button {
            Task { await tunnel.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(tunnel.isOn
                          ? LinearGradient(colors: [.green, .mint],
                                           startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color(uiColor: .tertiarySystemFill),
                                                    Color(uiColor: .secondarySystemFill)],
                                           startPoint: .top, endPoint: .bottom))
                    .frame(width: 168, height: 168)
                    .shadow(color: tunnel.isOn ? .green.opacity(0.35) : .clear, radius: 20)

                VStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 46, weight: .semibold))
                    Text(tunnel.isOn ? "关闭" : "一键连接")
                        .font(.headline)
                }
                .foregroundColor(tunnel.isOn ? .white : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(tunnel.isBusy)
    }

    private var statusArea: some View {
        VStack(spacing: 6) {
            Text(tunnel.statusText)
                .font(.subheadline.weight(.medium))
                .foregroundColor(tunnel.isOn ? .green : .secondary)
            if let s = tunnel.currentServer {
                Text(s.endpoint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if tunnel.activeConnections > 0 {
                Text("活动连接 \(tunnel.activeConnections)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 节点列表
    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("节点")
                .font(.headline)
                .padding(.horizontal)
            if tunnel.servers.isEmpty {
                Text("还没有节点，点右上角 + 添加一个 SOCKS5 服务器")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(tunnel.servers) { server in
                    serverRow(server)
                }
            }
        }
    }

    private func serverRow(_ server: ProxyServer) -> some View {
        let selected = tunnel.selectedID == server.id
        return HStack(spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(selected ? .accentColor : .secondary)
                .onTapGesture {
                    tunnel.selectedID = server.id
                    Task {
                        if tunnel.isOn {
                            await tunnel.stop()
                            await tunnel.start()
                        }
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.body)
                Text(server.endpoint).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let ms = pings[server.id] {
                Text("\(ms) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(ms < 300 ? .green : .orange)
            }
            Button {
                Task {
                    if let v = await tunnel.ping(server) { pings[server.id] = v }
                }
            } label: {
                Image(systemName: "bolt.horizontal.circle")
            }
            .buttonStyle(.borderless)
            Button {
                editing = server
                showEditor = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal)
        .contextMenu {
            Button("删除", role: .destructive) { tunnel.delete(server) }
        }
    }
}

// MARK: - 日志页
struct LogView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(tunnel.tunnelLog.isEmpty ? TunnelLog.read() : tunnel.tunnelLog)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("隧道日志")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空") {
                        TunnelLog.clear()
                        tunnel.tunnelLog = ""
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await tunnel.refreshStats() }
        }
    }
}

// MARK: - 分享辅助
struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
