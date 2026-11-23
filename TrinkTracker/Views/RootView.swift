import SwiftUI

/// Gerüst wie die Web-App (Minze & Honig 2.0): Titel „Trink-Tracker“ links,
/// rechts Symbol-Knöpfe für Nutzer und Einstellungen (immer erreichbar, auch
/// ohne Verbindung), darunter der Segmentschalter Heute | Statistik.
/// Nutzer und Einstellungen sind Unterseiten mit Zurück-Weg über die
/// Navigationsleiste.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    @State private var ansicht: Int = RootView.start.ansicht
    @State private var pfad: [Seite] = RootView.start.pfad

    enum Seite: Hashable { case nutzer, einstellungen }

    /// Nur für Debug-Builds: `-initialTab heute|statistik|nutzer|einstellungen`
    /// als Startargument öffnet direkt eine Ansicht (Screenshots, UI-Checks).
    private static var start: (ansicht: Int, pfad: [Seite]) {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "initialTab") {
        case "statistik": return (1, [])
        case "nutzer": return (0, [.nutzer])
        case "einstellungen": return (0, [.einstellungen])
        default: break
        }
        #endif
        return (0, [])
    }

    var body: some View {
        NavigationStack(path: $pfad) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MhKopf("Trink-Tracker", symbole: {
                        if store.loading {
                            ProgressView().controlSize(.small).tint(Mh.textSecondary)
                        }
                        MhSymbolButton("MhUsers", beschreibung: "Nutzer verwalten") { pfad.append(.nutzer) }
                        MhSymbolButton("MhSliders", beschreibung: "Einstellungen") { pfad.append(.einstellungen) }
                    })
                    MhSegmente(optionen: ["Heute", "Statistik"], gewaehlt: $ansicht)
                        .padding(.bottom, Mh.abstand6)
                    if ansicht == 1 {
                        StatsView()
                    } else {
                        HomeView()
                    }
                }
                .padding(.top, Mh.abstand2)
                .padding(.bottom, Mh.abstand8)
                .mhSeite()
            }
            .background(Mh.bg.ignoresSafeArea())
            // Grund hinter der Statusleiste, damit gescrollter Inhalt nicht
            // unter Uhrzeit und Symbolen durchläuft (Kopfleiste ist aus).
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(Mh.bg)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .navigationTitle("Trink-Tracker")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Seite.self) { seite in
                switch seite {
                case .nutzer: NutzerView()
                case .einstellungen: SettingsView()
                }
            }
        }
        .tint(Mh.link)
        .overlay(ToastOverlay(toast: toasts.current))
        .task {
            #if DEBUG
            // Nur mit `-MhBildschirmfotos 1` (UI-Test): erfundene Testdaten.
            await Bildschirmfotodaten.einspielen(settings: store.settings)
            #endif
            await store.refresh()
        }
        // Änderungen an Modus, URLs oder Keys bauen den Dienst neu — ohne
        // Neustart. Hier an der Wurzel, damit es auch nach dem Verlassen der
        // Einstellungen sicher ankommt.
        .onChange(of: settings.revision) { _, _ in store.settingsChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Beim Zurückkehren nachschicken, was offline liegen geblieben ist.
                Task { await store.flushQueue() }
            }
        }
    }
}

/// Rahmen einer Unterseite: Zurück-Weg über die Navigationsleiste (ohne
/// Titel dort), als erster Inhalt der Kopf mit H1 links und optional einer
/// kleinen Hauptaktion rechts (wie `ui_kopf()` mit Zurück-Link im Web).
struct Unterseitenrahmen<Inhalt: View, Hauptaktion: View>: View {
    let titel: String
    var untertitel: String?
    @ViewBuilder var inhalt: () -> Inhalt
    @ViewBuilder var hauptaktion: () -> Hauptaktion

    init(
        _ titel: String,
        untertitel: String? = nil,
        @ViewBuilder inhalt: @escaping () -> Inhalt,
        @ViewBuilder hauptaktion: @escaping () -> Hauptaktion = { EmptyView() }
    ) {
        self.titel = titel
        self.untertitel = untertitel
        self.inhalt = inhalt
        self.hauptaktion = hauptaktion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MhKopf(titel, untertitel: untertitel, hauptaktion: hauptaktion)
                inhalt()
            }
            .padding(.bottom, Mh.abstand8)
            .mhSeite()
        }
        .background(Mh.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
    }
}
