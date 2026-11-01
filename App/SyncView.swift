import SwiftUI
import UIKit

struct SyncView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss

    @State private var backend = SharedStore.syncConfig.baseURL
    @State private var account = SharedStore.syncConfig.username
    @State private var password = ""
    @State private var autoSync = SharedStore.syncConfig.autoSync
    @State private var message = SharedStore.syncConfig.lastMessage
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        statusCard
                        formCard
                        helpCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("线路同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tunnel.syncConfig.isConfigured ? Theme.ok : Color.white.opacity(0.2))
                    .frame(width: 7, height: 7)
                Text(tunnel.syncConfig.isConfigured ? "已连接网页后台" : "未连接后台")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("云端 \(tunnel.servers.filter { $0.isRemote }.count) 条")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            if !tunnel.syncConfig.lastMessage.isEmpty {
                Text(tunnel.syncConfig.lastMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            if tunnel.syncConfig.lastSync > 0 {
                let d = Date(timeIntervalSince1970: tunnel.syncConfig.lastSync)
                Text("上次同步 \(d.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var formCard: some View {
        VStack(spacing: 12) {
            input("后台地址", text: $backend, placeholder: "http://1.2.3.4:8787", keyboard: .URL)
            input("账号", text: $account, placeholder: "admin")
            input("密码", text: $password, placeholder: "••••••", secure: true)

            Toggle(isOn: $autoSync) {
                Text("启动 App 自动同步")
                    .font(.system(size: 13))
            }
            .tint(Theme.accent)
            .onChange(of: autoSync) { v in
                var c = tunnel.syncConfig
                c.autoSync = v
                tunnel.saveSync(c)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await doLogin() }
                } label: {
                    Text(busy ? "连接中…" : "登录并同步")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Theme.gradient))
                        .foregroundColor(.white)
                }
                .disabled(busy)

                Button {
                    Task { await doSync() }
                } label: {
                    Text("立即同步")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.vertical, 13)
                        .padding(.horizontal, 18)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.08)))
                        .foregroundColor(.white.opacity(0.8))
                }
                .disabled(busy || !tunnel.syncConfig.isConfigured)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(message.contains("失败") ? Theme.bad : .white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么用网页后台")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("1. 把 server/admin_server.py 放到你的电脑或服务器\n2. 运行 python admin_server.py --port 8787\n3. 浏览器打开 http://IP:8787 添加线路\n4. 这里填同样的地址和账号，点「登录并同步」")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.32))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 16)
    }

    private func input(_ title: String, text: Binding<String>, placeholder: String,
                       secure: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.35))
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text).keyboardType(keyboard)
                }
            }
            .font(.system(size: 13.5))
            .foregroundColor(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.05)))
        }
    }

    private func doLogin() async {
        busy = true
        let err = await tunnel.login(account: account, password: password, backend: backend)
        busy = false
        message = err ?? tunnel.syncConfig.lastMessage
    }

    private func doSync() async {
        busy = true
        let ok = await tunnel.syncNow()
        busy = false
        message = ok ? tunnel.syncConfig.lastMessage : "同步失败：\(tunnel.syncConfig.lastMessage)"
    }
}
