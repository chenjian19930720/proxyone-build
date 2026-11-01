import SwiftUI
import UIKit

/// 离线模式下手动添加/编辑线路
struct ServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var server: ProxyServer?
    var onSave: (ProxyServer) -> Void

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var group: String
    @State private var error: String?

    init(server: ProxyServer?, onSave: @escaping (ProxyServer) -> Void) {
        self.server = server
        self.onSave = onSave
        let s = server ?? ProxyServer()
        _name = State(initialValue: s.name)
        _host = State(initialValue: s.host)
        _port = State(initialValue: String(s.port))
        _username = State(initialValue: s.username)
        _password = State(initialValue: s.password)
        _group = State(initialValue: s.group)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        field(icon: "tag.fill", placeholder: "名称，如 香港01", text: $name)
                        field(icon: "server.rack", placeholder: "服务器 IP 或域名", text: $host,
                              keyboard: .URL)
                        field(icon: "number", placeholder: "端口，如 1080", text: $port,
                              keyboard: .numberPad)
                        field(icon: "person.fill", placeholder: "用户名（可空）", text: $username)
                        field(icon: "lock.fill", placeholder: "密码（可空）", text: $password, secure: true)
                        field(icon: "folder.fill", placeholder: "分组（可空）", text: $group)

                        if let error {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.bad)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            save()
                        } label: {
                            Text("保存线路")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gradient))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(server == nil ? "添加线路" : "编辑线路")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>,
                       secure: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 18)
            if secure {
                SecureField(placeholder, text: text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line, lineWidth: 1))
    }

    private func save() {
        guard let p = UInt16(port), p > 0 else {
            error = "端口必须是 1-65535 的数字"
            return
        }
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else {
            error = "服务器地址不能为空"
            return
        }
        var s = server ?? ProxyServer()
        s.name = name.isEmpty ? h : name
        s.host = h
        s.port = p
        s.username = username
        s.password = password
        s.group = group.isEmpty ? "本地" : group
        s.isRemote = false
        onSave(s)
        dismiss()
    }
}
