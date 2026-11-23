import SwiftUI

@main
struct TrinkTrackerApp: App {
    @State private var settings: AppSettings
    @State private var store: AppStore
    @State private var toasts = ToastCenter()

    init() {
        // Minze & Honig 2.0: Figtree registrieren, Navigationsleiste und
        // Segmente an die Rollen anpassen.
        MhDarstellung.einrichten()
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
