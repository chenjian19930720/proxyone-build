import SwiftUI

struct NodeListView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var search = ""
    @State private var refreshing = false
    @State private var showEditor = false
    @State private var editing: ProxyServer?
    @State private var showImport = false

    private var isOffline: Bool { SharedStore.offlineMode }

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
                    HStack(spacing: 15) {
                        if !isOffline {
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
                        }

                        Button {
                            Task { await tunnel.refreshLatencies() }
                        } label: {
                            Image(systemName: "speedometer")
                        }

                        if isOffline {
                            Button {
                                editing = nil
                                showEditor = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                ServerEditorView(server: editing) { saved in
                    tunnel.upsert(saved)
                }
            }
            .sheet(isPresented: $showImport) {
                ImportNodesView { nodes in
                    tunnel.importNodes(nodes)
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
                    HStack(spacing: 5) {
                        Text(node.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                        if node.proto != "socks5" {
                            Text(node.proto.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Theme.warn)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.warn.opacity(0.16)))
                        }
                    }
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
            Text(isOffline ? "本地还没有线路" : "没有可用线路")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text(isOffline
                 ? "离线模式：可以手动添加或批量导入 SOCKS5"
                 : "线路由管理员在网页后台配置\n同步后这里会自动出现")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.32))
                .multilineTextAlignment(.center)

            if isOffline {
                HStack(spacing: 12) {
                    Button {
                        showImport = true
                    } label: {
                        Text("批量导入")
                            .font(.system(size: 13.5, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Theme.gradient))
                            .foregroundColor(.white)
                    }
                    Button {
                        editing = nil
                        showEditor = true
                    } label: {
                        Text("手动添加")
                            .font(.system(size: 13.5, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.08)))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 6)
            } else {
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
            }

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

// MARK: - 批量导入（离线模式）
struct ImportNodesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parsed: [ProxyServer] = []
    var onDone: ([ProxyServer]) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: 12) {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                        .frame(height: 240)
                        .onChange(of: text) { v in parsed = NodeImport.parse(v) }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("一行一条，支持：")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                        Group {
                            Text("socks5://user:pass@1.2.3.4:1080")
                            Text("1.2.3.4:1080")
                            Text("1.2.3.4:1080:user:pass")
                            Text("香港01|1.2.3.4|1080|user|pass")
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    Button {
                        onDone(parsed)
                        dismiss()
                    } label: {
                        Text(parsed.isEmpty ? "没有可导入的行" : "导入 \(parsed.count) 条")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gradient))
                            .foregroundColor(.white)
                    }
                    .disabled(parsed.isEmpty)
                    .opacity(parsed.isEmpty ? 0.5 : 1)
                }
                .padding(20)
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
