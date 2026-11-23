#if DEBUG
import Foundation

/// Nur für die Bildschirmfotos im UI-Test (Workflow „Bildschirmfotos“).
///
/// Mit dem Startargument `-MhBildschirmfotos 1` stellt die App auf den lokalen
/// Modus und spielt erfundene Testdaten ein — der lokale Bestand im Simulator
/// wird dabei ersetzt. Ohne das Argument passiert nichts; in Release-Builds ist
/// die Datei nicht enthalten (kein Seeding, AGENTS.md Regel 10).
enum Bildschirmfotodaten {
    static var aktiv: Bool { UserDefaults.standard.bool(forKey: "MhBildschirmfotos") }

    @MainActor
    static func einspielen(settings: AppSettings) async {
        guard aktiv else { return }
        settings.setMode(.demo)
        let lokal = LocalService()
        try? await lokal.importAll(daten())
        await lokal.dispose()
        settings.setDefaultUserId(1)
        settings.setSelectedUserId(1)
    }

    /// Tagessummen der letzten Wochen für Anna (ab vorgestern rückwärts).
    private static let tagesmengen = [
        1750, 2150, 1400, 2300, 1900, 1150, 2050, 1600, 2250, 1850, 1300, 2000, 2400, 1700,
        1550, 2100, 1950, 1250, 2200, 1800, 1650, 2350, 1450, 2000, 1900, 1350, 2150, 1750,
    ]

    /// Backup-JSON wie `LocalService.exportAll()`, Zeiten relativ zu `jetzt`.
    static func daten(jetzt: Date = Date()) -> [String: Any] {
        var eintraege: [[String: Any]] = []
        var naechsteId = 1

        func eintrag(_ nutzer: Int, _ getraenk: String, _ ml: Int, minutenZurueck: Int) {
            eintraege.append([
                "id": naechsteId,
                "user_id": nutzer,
                "getraenk": getraenk,
                "menge_ml": ml,
                "create_time": iso8601String(jetzt.addingTimeInterval(-Double(minutenZurueck) * 60)),
            ])
            naechsteId += 1
        }

        // Heute
        eintrag(1, "Wasser", 250, minutenZurueck: 15)
        eintrag(1, "Tee", 300, minutenZurueck: 95)
        eintrag(1, "Wasser", 500, minutenZurueck: 180)
        eintrag(1, "Kaffee", 200, minutenZurueck: 300)
        eintrag(2, "Wasser", 500, minutenZurueck: 30)
        eintrag(2, "Apfelschorle", 330, minutenZurueck: 120)
        eintrag(2, "Wasser", 500, minutenZurueck: 240)
        eintrag(2, "Tee", 300, minutenZurueck: 360)
        eintrag(3, "Milch", 200, minutenZurueck: 60)
        eintrag(3, "Wasser", 125, minutenZurueck: 200)

        // Gestern
        let tag = 24 * 60
        eintrag(1, "Wasser", 500, minutenZurueck: tag + 60)
        eintrag(1, "Apfelschorle", 330, minutenZurueck: tag + 180)
        eintrag(1, "Tee", 300, minutenZurueck: tag + 300)
        eintrag(1, "Wasser", 500, minutenZurueck: tag + 420)
        eintrag(1, "Kaffee", 200, minutenZurueck: tag + 600)
        eintrag(2, "Wasser", 750, minutenZurueck: tag + 90)
        eintrag(2, "Tee", 300, minutenZurueck: tag + 400)

        // Ältere Tage für die Statistik
        let getraenke = ["Wasser", "Tee", "Apfelschorle"]
        for (index, summe) in tagesmengen.enumerated() {
            let tageZurueck = index + 2
            let erster = (summe * 3 / 10) / 10 * 10
            let zweiter = (summe * 3 / 10) / 10 * 10
            let teile = [erster, zweiter, summe - erster - zweiter]
            for (nummer, ml) in teile.enumerated() {
                eintrag(1, getraenke[nummer], ml, minutenZurueck: tageZurueck * tag + 120 + nummer * 200)
            }
            eintrag(2, "Wasser", 1200 + (index % 4) * 150, minutenZurueck: tageZurueck * tag + 240)
        }

        let nutzer: [[String: Any]] = [
            ["id": 1, "name": "Anna", "tagesziel_ml": 2000],
            ["id": 2, "name": "Ben", "tagesziel_ml": 1500],
            ["id": 3, "name": "Lina", "tagesziel_ml": 0],
        ]
        let favoriten: [[String: Any]] = [
            ["id": 1, "user_id": 1, "getraenk": "Wasser", "menge_ml": 250],
            ["id": 2, "user_id": 1, "getraenk": "Wasser", "menge_ml": 500],
            ["id": 3, "user_id": 1, "getraenk": "Tee", "menge_ml": 300],
            ["id": 4, "user_id": 1, "getraenk": "Apfelschorle", "menge_ml": 330],
            ["id": 5, "user_id": 1, "getraenk": "Kaffee", "menge_ml": 200],
            ["id": 6, "user_id": 2, "getraenk": "Wasser", "menge_ml": 500],
        ]
        return [
            "schema": LocalService.schemaVersion,
            "exported_at": iso8601String(jetzt),
            "users": nutzer,
            "entries": eintraege,
            "favoriten": favoriten,
        ]
    }
}
#endif
