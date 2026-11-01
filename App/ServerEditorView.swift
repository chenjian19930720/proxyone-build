import SwiftUI

struct ServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var server: ProxyServer?
    var onSave: (ProxyServer) -> Void

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
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
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("SOCKS5 服务器")) {
                    TextField("备注名称", text: $name)
                    TextField("地址（IP 或域名）", text: $host)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }
                Section(header: Text("认证（可选）")) {
                    TextField("用户名", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("密码", text: $password)
                }
                Section(footer: Text("所有 TCP/UDP 流量会经该 SOCKS5 服务器中转（UDP ASSOCIATE 需服务器支持，否则 DNS 走不通）。")) {
                    if let error {
                        Text(error).foregroundColor(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(server == nil ? "添加节点" : "编辑节点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        guard let p = UInt16(port), p > 0 else {
            error = "端口必须是 1-65535 的数字"
            return
        }
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "服务器地址不能为空"
            return
        }
        var s = server ?? ProxyServer()
        s.name = name.isEmpty ? host : name
        s.host = host.trimmingCharacters(in: .whitespaces)
        s.port = p
        s.username = username
        s.password = password
        onSave(s)
        dismiss()
    }
}
