import SwiftUI

@main
struct ProxyOneApp: App {
    @StateObject private var tunnel = TunnelManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tunnel)
                .task { await tunnel.load() }
        }
    }
}
