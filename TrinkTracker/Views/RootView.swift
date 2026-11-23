import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Tab = RootView.initialTab

    enum Tab: String, Hashable { case heute, statistik, einstellungen }

    /// Nur für Debug-Builds: `-initialTab statistik` als Startargument öffnet
    /// direkt einen Tab (Screenshots, UI-Checks im Simulator).
    private static var initialTab: Tab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "initialTab"), let tab = Tab(rawValue: raw) { return tab }
        #endif
        return .heute
    }

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Heute", systemImage: tab == .heute ? "drop.fill" : "drop") }
                .tag(Tab.heute)
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar") }
                .tag(Tab.statistik)
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(Tab.einstellungen)
        }
        .tint(c.isDark ? c.green300 : c.green600)
        .background(c.background)
        .overlay(ToastOverlay(toast: toasts.current))
        .task {
            #if DEBUG
            // Nur mit `-MhBildschirmfotos 1` (UI-Test): erfundene Testdaten.
            await Bildschirmfotodaten.einspielen(settings: store.settings)
            #endif
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Beim Zurückkehren nachschicken, was offline liegen geblieben ist.
                Task { await store.flushQueue() }
            }
        }
    }
}
