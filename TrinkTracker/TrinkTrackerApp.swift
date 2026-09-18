import SwiftUI

@main
struct TrinkTrackerApp: App {
    @State private var settings: AppSettings
    @State private var store: AppStore
    @State private var toasts = ToastCenter()

    init() {
        // Erster Start: lokaler Modus, leere Datenbank, keine vorkonfigurierten
        // Nutzer — die Familie legt alles selbst an (Spec 5 „Erster App-Start").
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: AppStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
                .environment(toasts)
        }
    }
}
