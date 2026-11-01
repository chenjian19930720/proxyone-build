import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tunnel: TunnelManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("加速", systemImage: "bolt.horizontal.circle.fill") }

            NodeListView()
                .tabItem { Label("线路", systemImage: "list.bullet.rectangle.portrait.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
