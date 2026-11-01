import SwiftUI
import UIKit

struct LoginView: View {
    var onSuccess: () -> Void

    @EnvironmentObject var tunnel: TunnelManager

    @State private var backend = SharedStore.syncConfig.baseURL.isEmpty
        ? "" : SharedStore.syncConfig.baseURL
    @State private var account = SharedStore.accountName
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

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
                    Spacer(minLength: 44)

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
                        field(icon: "server.rack",
                              placeholder: "服务器地址，如 http://1.2.3.4:8787",
                              text: $backend, keyboard: .URL)

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
                        .disabled(busy || account.isEmpty || backend.isEmpty)
                        .opacity((account.isEmpty || backend.isEmpty) ? 0.5 : 1)
                        .padding(.top, 4)

                        if let error {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.bad)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                                .padding(.top, 2)
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
                        Text("账号需由管理员在网页后台开通后才能登录")
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
