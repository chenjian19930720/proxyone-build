import SwiftUI
import Combine

@main
struct ProxyOneApp: App {
    @StateObject private var tunnel = TunnelManager()
    /// 0 = 启动画面, 1 = 登录, 2 = 主界面
    @State private var stage = 0

    var body: some Scene {
        WindowGroup {
            ZStack {
                if stage == 0 {
                    SplashView {
                        stage = SharedStore.isLoggedIn ? 2 : 1
                        if stage == 2 { bootstrap() }
                    }
                    .transition(.opacity)
                } else if stage == 1 {
                    LoginView {
                        stage = 2
                        bootstrap()
                    }
                    .transition(.opacity)
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .environmentObject(tunnel)
            .preferredColorScheme(.dark)
            .task {
                await tunnel.load()
                await tunnel.pullConfig()
            }
            .onReceive(NotificationCenter.default.publisher(for: .proxyOneLogout)) { _ in
                withAnimation { stage = 1 }
            }
        }
    }

    private func bootstrap() {
        Task {
            if SharedStore.syncConfig.autoSync, SharedStore.syncConfig.isConfigured {
                _ = await tunnel.syncNow()
            }
            if SharedStore.autoConnect, !tunnel.isOn, tunnel.currentServer != nil {
                await tunnel.start()
            }
        }
    }
}
