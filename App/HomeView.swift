import SwiftUI

struct HomeView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var pulse = false
    @State private var exitIP = "—"
    @State private var loadingIP = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ipHeader
                        powerButton
                        statusChip
                        if let s = tunnel.currentServer {
                            currentCard(s)
                        } else {
                            emptyCard
                        }
                        quickNodes
                        footerHint
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("加速")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Image(systemName: "ladybug")
                    }
                }
            }
            .onAppear {
                pulse = true
                if tunnel.isOn { Task { await refreshIP() } }
            }
            .onChange(of: tunnel.status) { status in
                if status == .connected {
                    Task { await refreshIP() }
                } else if status == .disconnected || status == .invalid {
                    exitIP = "—"
                }
            }
        }
    }

    // MARK: 顶部 IP
    private var ipHeader: some View {
        VStack(spacing: 6) {
            Text(tunnel.isOn ? "当前出口 IP" : "本机 IP")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
            Button {
                Task { await refreshIP() }
            } label: {
                HStack(spacing: 8) {
                    Text(loadingIP ? "查询中…" : exitIP)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    // MARK: 大按钮
    private var powerButton: some View {
        Button {
            Task { await tunnel.toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(tunnel.isOn ? 0.45 : 0.12), lineWidth: 1.5)
                    .frame(width: 212, height: 212)
                    .scaleEffect(pulse && tunnel.isOn ? 1.16 : 1.0)
                    .opacity(pulse && tunnel.isOn ? 0 : 0.9)
                    .animation(tunnel.isOn
                               ? .easeOut(duration: 1.8).repeatForever(autoreverses: false)
                               : .default,
                               value: pulse)

                Circle()
                    .fill(tunnel.isOn
                          ? AnyShapeStyle(Theme.gradient)
                          : AnyShapeStyle(Theme.cardHi))
                    .frame(width: 188, height: 188)
                    .shadow(color: tunnel.isOn ? Theme.accent.opacity(0.5) : .clear, radius: 26)

                VStack(spacing: 10) {
                    Image(systemName: tunnel.isBusy ? "arrowtriangle.right.circle" : "power")
                        .font(.system(size: 42, weight: .medium))
                    Text(buttonTitle)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(tunnel.isOn ? .white : .white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .disabled(tunnel.isBusy)
    }

    private var buttonTitle: String {
        switch tunnel.status {
        case .connected: return "断开"
        case .connecting: return "连接中"
        case .disconnecting: return "断开中"
        case .reasserting: return "重连中"
        default: return "一键连接"
        }
    }

    private var statusChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tunnel.isOn ? Theme.ok : Color.white.opacity(0.25))
                .frame(width: 7, height: 7)
            Text(tunnel.statusText)
                .font(.system(size: 13))
                .foregroundColor(tunnel.isOn ? Theme.ok : .white.opacity(0.5))
            if let ms = tunnel.currentServer?.latency {
                Text("·")
                    .foregroundColor(.white.opacity(0.25))
                Text("\(ms) ms")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Theme.latencyColor(tunnel.currentServer?.latencyLevel ?? -1))
            }
        }
    }

    // MARK: 当前线路
    private func currentCard(_ s: ProxyServer) -> some View {
        NavigationLink {
            NodeListView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.gradientSoft)
                        .frame(width: 44, height: 44)
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 19))
                        .foregroundColor(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(s.endpoint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Text("切换")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var emptyCard: some View {
        NavigationLink {
            NodeListView()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.3))
                Text("还没有线路")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text("去「线路」页添加 SOCKS5 服务器，或整段粘贴批量导入")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: 推荐线路
    private var quickNodes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("延迟最低")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Button {
                    Task { await tunnel.refreshLatencies() }
                } label: {
                    Text("重新测速")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
                }
            }

            let list = tunnel.fastestNodes(limit: 3)
            if list.isEmpty {
                Text("点「重新测速」后这里会列出最快的线路")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
            } else {
                ForEach(list) { node in
                    Button {
                        Task { await tunnel.activate(node) }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.latencyColor(node.latencyLevel).opacity(0.16))
                                .frame(width: 8, height: 8)
                                .padding(.leading, 2)
                            Text(node.name)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            if let ms = node.latency {
                                Text("\(ms) ms")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(Theme.latencyColor(node.latencyLevel))
                            }
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.accent.opacity(0.7))
                        }
                        .card(padding: 14, radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footerHint: some View {
        Text("全局模式：TCP / UDP / DNS 全部经线路转发")
            .font(.system(size: 10.5))
            .foregroundColor(.white.opacity(0.22))
            .padding(.top, 6)
    }

    private func refreshIP() async {
        loadingIP = true
        exitIP = await tunnel.checkExitIP()
        loadingIP = false
    }
}
