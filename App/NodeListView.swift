import SwiftUI

struct NodeListView: View {
    @EnvironmentObject var tunnel: TunnelManager

    @State private var search = ""
    @State private var showEditor = false
    @State private var editing: ProxyServer?
    @State private var showImport = false

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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            Task { await tunnel.refreshLatencies() }
                        } label: {
                            Image(systemName: "speedometer")
                        }
                        Button {
                            editing = nil
                            showEditor = true
                        } label: {
                            Image(systemName: "plus")
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                tunnel.delete(node)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                editing = node
                showEditor = true
            } label: {
                Label("编辑", systemImage: "slider.horizontal.3")
            }
            .tint(Theme.accent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
            Text("还没有线路")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("点左上角导入，或右上角 + 添加一条 SOCKS5")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
            HStack(spacing: 12) {
                Button("批量导入") { showImport = true }
                    .buttonStyle(PillButton(style: .filled))
                Button("手动添加") { editing = nil; showEditor = true }
                    .buttonStyle(PillButton(style: .plain))
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - 批量导入
struct ImportNodesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parsed: [ProxyServer] = []
    var onDone: ([ProxyServer]) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: 14) {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                        .frame(height: 240)
                        .onChange(of: text) { value in
                            parsed = NodeImport.parse(value)
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("支持的写法（一行一条）")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                        Group {
                            Text("socks5://user:pass@1.2.3.4:1080")
                            Text("1.2.3.4:1080")
                            Text("1.2.3.4:1080:user:pass")
                            Text("香港01|1.2.3.4|1080|user|pass")
                            Text("香港01 1.2.3.4 1080")
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
                        Text(parsed.isEmpty ? "没有可导入的行" : "导入 \(parsed.count) 条线路")
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

// MARK: - 胶囊按钮样式
struct PillButton: ButtonStyle {
    enum Style: Equatable { case filled, plain }
    var style: Style = .plain

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(style == .filled ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
            )
            .foregroundColor(style == .filled ? .white : .white.opacity(0.7))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
