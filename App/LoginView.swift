import SwiftUI
import UIKit

struct LoginView: View {
    var onSuccess: () -> Void

    @EnvironmentObject var tunnel: TunnelManager

    @State private var backend: String = {
        let saved = SharedStore.syncConfig.baseURL
        if !saved.isEmpty { return saved }
        return AppConfig.defaultBackend
    }()
    @State private var account = SharedStore.accountName
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    /// 只有内置地址为空时才默认展开服务器输入
    @State private var showServer = !AppConfig.hasBuiltinBackend
    @State private var showRegister = false
    @State private var showOfflineAuth = false
    @State private var offlineInput = ""
    @State private var offlineError: String?

    private var canSubmit: Bool {
        !busy && !account.isEmpty && !password.isEmpty && !backend.isEmpty
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()

            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.28), .clear],
                                     center: .center, startRadius: 10, endRadius: 240))
                .frame(width: 460, height: 460)
                .offset(y: -220)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 52)

                    VStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Theme.gradient)
                                .frame(width: 78, height: 78)
                                .shadow(color: Theme.accent.opacity(0.45), radius: 22)
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                        }
                        VStack(spacing: 4) {
                            Text("陈先生IP系统")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(.white)
                            Text("定制版")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent.opacity(0.16)))
                        }
                    }
                    .padding(.bottom, 30)

                    VStack(spacing: 13) {
                        field(icon: "person.fill", placeholder: "账号", text: $account)

                        field(icon: "lock.fill", placeholder: "密码", text: $password, secure: true)

                        Button {
                            Task { await doLogin() }
                        } label: {
                            HStack {
                                if busy {
                                    ProgressView().tint(.white).padding(.trailing, 4)
                                }
                                Text(busy ? "验证中…" : "登 录")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gradient))
                            .foregroundColor(.white)
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                        .padding(.top, 4)

                        if let error {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.bad)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }

                        // 服务器（默认隐藏，只有需要时展开）
                        if showServer {
                            field(icon: "server.rack",
                                  placeholder: "服务器地址，如 http://1.2.3.4:8787",
                                  text: $backend, keyboard: .URL)
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.shield")
                                    .font(.system(size: 9))
                                Text("服务器：\(AppConfig.backendLabel)")
                                    .font(.system(size: 10, design: .monospaced))
                                Text("·")
                                Button("修改") {
                                    withAnimation { showServer = true }
                                }
                                .font(.system(size: 10))
                                .foregroundColor(Theme.accent)
                            }
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.top, 2)
                        }

                        Button {
                            showRegister = true
                        } label: {
                            Text("没有账号？申请开通")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        .padding(.top, 6)

                        Divider().overlay(Theme.line).padding(.vertical, 4)

                        Button {
                            if AppConfig.offlineLockEnabled {
                                offlineInput = ""
                                offlineError = nil
                                showOfflineAuth = true
                            } else {
                                enterOffline()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                Text(AppConfig.offlineLockEnabled
                                     ? "离线模式 · 需要访问密码"
                                     : "离线模式 · 本地管理线路")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.card.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                        Text("账号需由管理员开通后才能登录")
                            .font(.system(size: 10.5))
                    }
                    .foregroundColor(.white.opacity(0.28))
                    .padding(.top, 16)

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 26)
            }
        }
        .onAppear {
            if account.isEmpty { account = SharedStore.accountName }
        }
        .sheet(isPresented: $showRegister) {
            RegisterView(backend: backend) { acc, pwd in
                account = acc
                password = pwd
                error = "账号已提交，等管理员在后台开通后即可登录"
            }
        }
        .sheet(isPresented: $showOfflineAuth) {
            offlineAuthSheet
        }
    }

    // MARK: 离线模式密码
    private var offlineAuthSheet: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.14)).frame(width: 72, height: 72)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.accent)
                    }
                    Text("离线模式")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("离线版线路存在本机，需要访问密码才能进入")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    SecureField("访问密码", text: $offlineInput)
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.06)))
                        .padding(.horizontal, 40)
                        .padding(.top, 6)

                    if let offlineError {
                        Text(offlineError)
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.bad)
                    }

                    Button {
                        verifyOffline()
                    } label: {
                        Text("进入离线模式")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gradient))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 4)

                    Button("取消") { showOfflineAuth = false }
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(400)])
    }

    private func verifyOffline() {
        if offlineInput == AppConfig.offlinePassword {
            showOfflineAuth = false
            enterOffline()
        } else {
            offlineError = "密码错误"
            offlineInput = ""
        }
    }

    private func enterOffline() {
        SharedStore.offlineMode = true
        SharedStore.isLoggedIn = true
        SharedStore.accountName = "离线用户"
        onSuccess()
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

    private func doLogin() async {
        busy = true
        error = nil
        let err = await tunnel.login(account: account, password: password, backend: backend)
        busy = false
        if let err {
            error = err
        } else {
            SharedStore.isLoggedIn = true
            onSuccess()
        }
    }
}
