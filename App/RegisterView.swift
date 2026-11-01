import SwiftUI
import UIKit

struct RegisterView: View {
    var backend: String
    var onRegistered: (String, String) -> Void      // (账号, 密码) 回填到登录页

    @Environment(\.dismiss) private var dismiss

    @State private var account = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var contact = ""
    @State private var busy = false
    @State private var error: String?
    @State private var done = false
    @State private var serverMessage = ""

    private var canSubmit: Bool {
        !busy && account.count >= 3 && password.count >= 6 && password == confirm
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    if done {
                        successView
                    } else {
                        formView
                    }
                }
            }
            .navigationTitle("申请开通账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: 表单
    private var formView: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("注册后需要管理员在后台开通，才能登录使用")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.45))
                Text("提交后把这个账号发给管理员，或等管理员在后台看到后开通")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            field(icon: "person.fill", placeholder: "账号（至少 3 位）", text: $account)
            field(icon: "lock.fill", placeholder: "密码（至少 6 位）", text: $password, secure: true)
            field(icon: "lock.rotation", placeholder: "确认密码", text: $confirm, secure: true)
            field(icon: "envelope.fill", placeholder: "联系方式（邮箱 / 微信，便于管理员联系）", text: $contact)

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white).padding(.trailing, 4) }
                    Text(busy ? "提交中…" : "提交申请")
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

            if !password.isEmpty && password != confirm {
                Text("两次密码不一致")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.warn)
            }

            if let error {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.bad)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 20)
        }
        .padding(20)
    }

    // MARK: 成功
    private var successView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            ZStack {
                Circle()
                    .fill(Theme.ok.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Theme.ok)
            }
            Text("申请已提交")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
            Text("账号 \(account) 已进入待审核。\n管理员开通后就能直接登录。")
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if !serverMessage.isEmpty {
                Text(serverMessage)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.25))
            }

            Button {
                onRegistered(account, password)
                dismiss()
            } label: {
                Text("返回登录")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gradient))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)

            Spacer(minLength: 30)
        }
        .padding(24)
    }

    private func field(icon: String, placeholder: String, text: Binding<String>,
                       secure: Bool = false) -> some View {
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
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line, lineWidth: 1))
    }

    private func submit() async {
        busy = true
        error = nil
        do {
            let msg = try await SyncService.register(base: backend, user: account,
                                                     pass: password, contact: contact)
            serverMessage = msg
            done = true
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
