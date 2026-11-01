import SwiftUI

struct HomeView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @Binding var tab: Int

    @State private var pulse = false
    @State private var exitIP = "获取中…"
    @State private var loadingIP = false
    @State private var showDebug = false
    @State private var alwaysOnLocal = SharedStore.alwaysOn

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    brandHeader
                    ipHeader
                    powerButton
                    statusChip
                    alwaysOnCard
                    currentCard
                    quickNodes
                    footerHint
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showDebug) { DebugView() }
        .onAppear {
            pulse = true
            alwaysOnLocal = tunnel.alwaysOn
            Task { await refreshIP() }
        }
        .onChange(of: tunnel.status) { status in
            if status == .connected || status == .disconnected || status == .invalid {
                Task { await refreshIP() }
            }
        }
        .onChange(of: tunnel.networkUp) { up in
            if up { Task { await refreshIP() } }
        }
        .onChange(of: tunnel.alwaysOn) { v in
            alwaysOnLocal = v
        }
    }

    // MARK: 品牌
    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.gradient)
                    .frame(width: 34, height: 34)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("陈先生IP系统")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text("定制版")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.accent.opacity(0.16)))
            }
            Spacer()
            Button {
                showDebug = true
            } label: {
                Image(systemName: "ladybug")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
        }
    }

    // MARK: IP
    private var ipHeader: some View {
        VStack(spacing: 5) {
            Text(tunnel.isOn ? "出口 IP" : "本机 IP")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.05)))

            Button {
                Task { await refreshIP() }
            } label: {
                HStack(spacing: 8) {
                    Text(loadingIP ? "查询中…" : exitIP)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 大按钮
    private var powerButton: some View {
        Button {
            Task { await tunnel.toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(tunnel.isOn ? 0.45 : 0.12), lineWidth: 1.5)
                    .frame(width: 208, height: 208)
                    .scaleEffect(pulse && tunnel.isOn ? 1.15 : 1.0)
                    .opacity(pulse && tunnel.isOn ? 0 : 0.9)
                    .animation(tunnel.isOn
                               ? .easeOut(duration: 1.8).repeatForever(autoreverses: false)
                               : .default,
                               value: pulse)

                Circle()
                    .fill(tunnel.isOn ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.cardHi))
                    .frame(width: 184, height: 184)
                    .shadow(color: tunnel.isOn ? Theme.accent.opacity(0.5) : .clear, radius: 26)

                VStack(spacing: 9) {
                    Image(systemName: "power")
                        .font(.system(size: 40, weight: .medium))
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
                .font(.system(size: 12.5))
                .foregroundColor(tunnel.isOn ? Theme.ok : .white.opacity(0.45))
            if let s = tunnel.currentServer, let ms = s.latency {
                Text("·").foregroundColor(.white.opacity(0.2))
                Text("\(ms) ms")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(Theme.latencyColor(s.latencyLevel))
            }
        }
    }

    // MARK: 强制保持连接
    private var alwaysOnCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(alwaysOnLocal ? Theme.accent.opacity(0.16) : Color.white.opacity(0.05))
                    .frame(width: 34, height: 34)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(alwaysOnLocal ? Theme.accent : .white.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("强制保持连接")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("断网自动重连 · 有网秒连 · 后台不断")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.32))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alwaysOnLocal },
                set: { v in
                    alwaysOnLocal = v
                    Task { await tunnel.setAlwaysOn(v) }
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
            .scaleEffect(0.85)
        }
        .card(padding: 14, radius: 16)
    }

    // MARK: 当前线路
    private var currentCard: some View {
        Button {
            tab = 1
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.gradientSoft)
                        .frame(width: 42, height: 42)
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tunnel.currentServer?.name ?? "还没有线路")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Text(tunnel.currentServer?.endpoint ?? "点这里去添加或批量导入")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                Text(tunnel.currentServer == nil ? "添加" : "切换")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }
            .card(padding: 14, radius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: 推荐线路
    private var quickNodes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("延迟最低")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    Task { await tunnel.refreshLatencies() }
                } label: {
                    Text("重新测速")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.accent)
                }
            }

            let list = tunnel.fastestNodes(limit: 3)
            if list.isEmpty {
                Text("点「重新测速」后这里会列出最快的 3 条线路")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 13, radius: 14)
            } else {
                ForEach(list) { node in
                    Button {
                        Task { await tunnel.activate(node) }
                    } label: {
                        HStack(spacing: 11) {
                            Circle()
                                .fill(Theme.latencyColor(node.latencyLevel))
                                .frame(width: 6, height: 6)
                            Text(node.name)
                                .font(.system(size: 13.5))
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                            Spacer()
                            if let ms = node.latency {
                                Text("\(ms) ms")
                                    .font(.system(size: 11.5, design: .rounded))
                                    .foregroundColor(Theme.latencyColor(node.latencyLevel))
                            }
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.accent.opacity(0.6))
                        }
                        .card(padding: 13, radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footerHint: some View {
        Text("全局模式：TCP / UDP / DNS 全部经线路转发")
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.2))
            .padding(.top, 4)
    }

    private func refreshIP() async {
        guard !loadingIP else { return }
        loadingIP = true
        exitIP = await tunnel.checkExitIP()
        loadingIP = false
    }
}
