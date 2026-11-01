import SwiftUI

struct NodeListView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var search = ""
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()

                if tunnel.servers.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("线路")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索线路")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            Task {
                                refreshing = true
                                _ = await tunnel.syncNow()
                                await tunnel.refreshLatencies()
                                refreshing = false
                            }
                        } label: {
                            if refreshing {
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(refreshing)

                        Button {
                            Task { await tunnel.refreshLatencies() }
                        } label: {
                            Image(systemName: "speedometer")
                        }
                    }
                }
            }
        }
    }

    // MARK: 列表
    private var filtered: [ProxyServer] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return tunnel.servers }
        return tunnel.servers.filter {
            $0.name.lowercased().contains(q) || $0.endpoint.lowercased().contains(q)
        }
    }

    private var groups: [String] {
        Array(Set(filtered.map { $0.displayGroup })).sorted()
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.self) { group in
                Section {
                    ForEach(filtered.filter { $0.displayGroup == group }) { node in
                        row(node)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(group)
                        Text("\(filtered.filter { $0.displayGroup == group }.count)")
                            .foregroundColor(.white.opacity(0.25))
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private func row(_ node: ProxyServer) -> some View {
        let selected = tunnel.selectedID == node.id
        return Button {
            Task { await tunnel.activate(node) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.gradientSoft) : AnyShapeStyle(Color.white.opacity(0.05)))
                        .frame(width: 38, height: 38)
                    Image(systemName: selected ? "checkmark" : "globe.asia.australia")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selected ? Theme.accent : .white.opacity(0.35))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(node.endpoint)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }

                Spacer()

                if let ms = node.latency {
                    HStack(spacing: 1) {
                        Text("\(ms)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.latencyColor(node.latencyLevel))
                        Text("ms")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.25))
                    }
                } else {
                    Text("未测")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.card)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
            Text("没有可用线路")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("线路由管理员在网页后台配置\n同步后这里会自动出现")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.32))
                .multilineTextAlignment(.center)

            Button {
                Task {
                    refreshing = true
                    _ = await tunnel.syncNow()
                    refreshing = false
                }
            } label: {
                Text(refreshing ? "同步中…" : "立即同步")
                    .font(.system(size: 13.5, weight: .medium))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.gradient))
                    .foregroundColor(.white)
            }
            .disabled(refreshing)
            .padding(.top, 6)

            if !tunnel.syncConfig.lastMessage.isEmpty {
                Text(tunnel.syncConfig.lastMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}
