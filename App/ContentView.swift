import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("加速", systemImage: "bolt.horizontal.circle.fill") }
                .tag(0)

            NodeListView()
                .tabItem { Label("线路", systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(1)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
