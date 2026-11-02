import SwiftUI
import UIKit
import Combine

struct DebugView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss

    @State private var log = ""
    @State private var autoRefresh = true
    @State private var exitIP = "-"
    @State private var exitIPLoading = false
    @State private var probe: TunnelManager.ProbeResult?
    @State private var probing = false
    @State private var shareURL: URL?

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("隧道状态")) {
                    row("VPN 状态", tunnel.statusText,
                        color: tunnel.isOn ? .green : .secondary)
                    row("服务器", tunnel.currentServer?.endpoint ?? "-")
                    row("活动连接", "\(tunnel.activeConnections)")
                    if let err = tunnel.lastError {
                        row("最近错误", err, color: .red)
                    }
                }

                Section(header: Text("出口 IP"),
                        footer: Text("已连接时这里显示的是代理出口 IP；未连接时是本机出口。走的是 App 自己的 socket 请求，会经过隧道。")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exitIP).font(.system(.footnote, design: .monospaced))
                            if !tunnel.exitIPLocation.isEmpty {
                                Text(tunnel.exitIPLocation)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button(exitIPLoading ? "查询中…" : "查询") {
                            Task { await refreshExitIP() }
                        }
                        .disabled(exitIPLoading)
                    }
                    if !tunnel.lastIPError.isEmpty {
                        Text(tunnel.lastIPError)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Theme.warn)
                    }
                }

                Section(header: Text("隧道流量"),
                        footer: Text(tunnel.statsError.isEmpty
                                     ? "数据来自隧道扩展，每 1.5 秒刷新一次。"
                                     : "扩展通信异常：\(tunnel.statsError)")) {
                    row("上行", humanBytes(tunnel.bytesUp))
                    row("下行", humanBytes(tunnel.bytesDown))
                    row("活动连接", "\(tunnel.activeConnections)")
                }

                Section(header: Text("经过代理的连接"),
                        footer: Text("这里列出手机所有 App 经过隧道的目标地址。如果微信、浏览器、支付宝用到的 IP 都出现在这里，说明全局代理生效。系统不提供 App 名称，只能看到目标 IP。")) {
                    if tunnel.recentTargets.isEmpty {
                        Text("还没有连接记录")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        Text(tunnel.recentTargets)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineSpacing(2)
                    }
                }

                Section(header: Text("SOCKS5 诊断"),
                        footer: Text("直接从我这边探测服务器端口和 SOCKS5 握手，能区分「TCP 连不上 / 不是 SOCKS5 / 密码错 / 正常」。")) {
                    Button(probing ? "探测中…" : "重新探测") {
                        Task { await runProbe() }
                    }
                    .disabled(probing)
                    if let p = probe {
                        Text(p.detail)
                            .font(.footnote)
                            .foregroundColor(p.ok ? .green : .red)
                    }
                }

                Section(header: HStack {
                    Text("扩展日志")
                    Spacer()
                    Toggle("自动刷新", isOn: $autoRefresh).labelsHidden()
                }, footer: Text("日志写在 App Group 共享目录，主 App 和扩展都能读写。连接失败时先看这里。")) {
                    ScrollView {
                        Text(log.isEmpty ? "(空)" : log)
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 260)
                }

                Section(header: Text("环境")) {
                    row("扩展 Bundle ID", TunnelManager.tunnelBundleID)
                    row("App Group", SharedStore.appGroup)
                    row("MTU", "1400")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("调试")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        TunnelLog.clear()
                        log = ""
                    } label: { Image(systemName: "trash") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            exportLog()
                        } label: { Image(systemName: "square.and.arrow.up") }
                        Button("完成") { dismiss() }
                    }
                }
            }
            .onAppear {
                log = tunnel.tunnelLog
                Task { await tunnel.refreshStats(); await tunnel.pullLog() }
            }
            .onReceive(timer) { _ in
                if autoRefresh {
                    Task { await tunnel.refreshStats(); await tunnel.pullLog() }
                    log = tunnel.tunnelLog
                }
            }
            .sheet(item: Binding(
                get: { shareURL.map(ShareItem.init) },
                set: { if $0 == nil { shareURL = nil } }
            )) { item in
                ActivityView(url: item.url)
            }
        }
    }

    private func humanBytes(_ b: UInt64) -> String {
        let kb = Double(b) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.2f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }

    private func row(_ title: String, _ value: String, color: Color = .primary) -> some View {        HStack(alignment: .top) {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .multilineTextAlignment(.trailing)
                .font(.footnote)
        }
    }

    private func refreshExitIP() async {
        exitIPLoading = true
        exitIP = await tunnel.checkExitIP()
        exitIPLoading = false
    }

    private func runProbe() async {
        guard let s = tunnel.currentServer else {
            probe = TunnelManager.ProbeResult(ok: false, ms: 0, detail: "还没有配置节点")
            return
        }
        probing = true
        probe = await tunnel.probe(s)
        probing = false
    }

    private func exportLog() {
        let body = """
        == ProxyOne 诊断 ==
        时间: \(Date())
        状态: \(tunnel.statusText)
        服务器: \(tunnel.currentServer?.endpoint ?? "-")
        出口IP: \(exitIP)
        探测: \(probe?.detail ?? "-")
        扩展: \(TunnelManager.tunnelBundleID)
        Group: \(SharedStore.appGroup)

        == 日志 ==
        \(log)
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("proxyone-diagnose.txt")
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
        shareURL = url
    }
}
