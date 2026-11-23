# AGENTS.md — Trink-Tracker (iOS, nativ)

Leitfaden für alle Coding-Agenten in diesem Repository. Das Projekt ist der
native SwiftUI-Port der früheren Flutter-App `TrinkTracker-Flutter`; **das
Flutter-Repo existiert nicht mehr.** Alles Wissen daraus, das hier noch zählt,
steht in dieser Datei, in `README.md` und im Code selbst.

Sprache: UI-Texte, Kommentare, Commit-Messages und Doku sind **Deutsch**.

---

## 1. Was die App ist

Getränke-Tracker für eine Familie: mehrere Nutzer, Tagesziele, Favoriten als
Schnellwahl, Statistik (7 Tage / 30 Tage), vier Verbindungsmodi. Umsetzung der
internen „App-Spezifikation v1.2“ (Spec-Verweise in Kommentaren wie „Spec 3.1“
beziehen sich darauf; das Dokument liegt nicht im Repo).

**Mandantenneutral:** Es gibt **keine** vordefinierte URL, keinen Key, keine
Nutzer — auch nicht in Debug-Builds. Jede Familie trägt alles selbst ein.

---

## 2. Bauen, testen, ausführen

```bash
open TrinkTracker.xcodeproj                      # Xcode 27, iOS 17.0+
xcodebuild -scheme TrinkTracker -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme TrinkTracker -destination 'platform=iOS Simulator,name=iPhone 17' test
```

* Keine externen Abhängigkeiten, kein SPM, keine Pods. Nur System-Frameworks
  (SwiftUI, Charts, Observation, Security, SQLite3, UniformTypeIdentifiers).
* Tests sind **Swift Testing** (`import Testing`, `@Test`, `#expect`), kein XCTest.
* Signing: Team `2HNRMGYGMU`, Bundle-ID `org.dwarftsch.trinktracker`, automatisch.
  Für CI/Simulator: `CODE_SIGNING_ALLOWED=NO`.
* `SWIFT_VERSION = 5.0`. Der Code ist trotzdem concurrency-sauber geschrieben
  (`@MainActor`-Store, Actor für SQLite, `Sendable`-Modelle) — Warnungen der
  Art „this is an error in Swift 6“ **nicht** ignorieren, sondern beheben.
* Ziel: **null Compiler-Warnungen.** Vor jedem Abschluss `build` + `test` laufen lassen.

### Simulator-Hilfen (nur Debug)

* `-initialTab heute|statistik|nutzer|einstellungen` als Startargument öffnet eine
  Ansicht direkt (`xcrun simctl launch <UDID> org.dwarftsch.trinktracker -initialTab statistik`).
* `-MhBildschirmfotos 1` stellt auf den lokalen Modus und spielt erfundene
  Testdaten ein (Anna, Ben, Lina; `Debug/Bildschirmfotodaten.swift`). Ersetzt den
  lokalen Bestand im Simulator. Nur Debug-Builds, genutzt vom UI-Test
  `TrinkTrackerUITests/ScreenshotTests`.
* Startargumente kommen als **Strings** in die UserDefaults. Ints wie
  `selectedUserId`/`defaultUserId` deshalb so setzen:
  `xcrun simctl spawn <UDID> defaults write org.dwarftsch.trinktracker trinktracker_settings.defaultUserId -int 1`
* Testdaten: SQLite-Datei liegt unter
  `$(xcrun simctl get_app_container <UDID> org.dwarftsch.trinktracker data)/Documents/trinktracker.db`
  und lässt sich mit `sqlite3` direkt befüllen (Schema siehe `LocalService.createSchema`).
* Screenshot: `xcrun simctl io <UDID> screenshot out.png`; Dark Mode:
  `xcrun simctl ui <UDID> appearance dark`.

### Simulator-Rauschen, das **nicht** aus der App kommt

Diese Konsolenzeilen sind bekannt und harmlos — nicht „fixen“:
`cannot add handler to 0 from 0`, `PointerUI … default-service`,
`CHHapticPattern … hapticpatternlibrary.plist` (Simulator hat keine Haptik),
`UIKBDynamicRenderFactory`, `TUIPredictionViewCell`-Constraints (Tastatur),
`IOSurfaceClientSetSurfaceNotify`, `Unable to get ISSymbol for UTI: com.apple.ios-simulator`,
`Invalid UIScreen coordinate space conversion`.

---

## 3. Architektur

```
TrinkTracker/
  TrinkTrackerApp.swift        Einstieg; legt AppSettings, AppStore, ToastCenter ins Environment
  Models/Models.swift          TrinkUser/TrinkEntry/TrinkFavorite/TodayStats/StatsBundle
                               + tolerantes JSON (asInt/asBool/asString) + Zeitformate
  Util/BerlinTime.swift        Europe/Berlin per EU-DST-Regel, ohne Zeitzonen-DB
  Settings/
    ConnectionMode.swift       demo | apiKey | api (mTLS) | cloudflare  (+ ConnectionKind lokal/API)
    AppSettings.swift          @Observable @MainActor; UserDefaults + Keychain; `revision` zählt Verbindungsänderungen
    KeychainStore.swift        generische Passwörter, ein Eintrag je Schlüssel
    LegacyFlutterMigration.swift  einmalige Übernahme der Flutter-Einstellungen (Abschnitt 6)
  Services/
    TrinkEntryService.swift    Protokoll über alle Modi (async throws)
    APIService.swift           URLSession; Redirects blockiert; URLError → TrinkError-Mapping
    ClientCertificateStore.swift  p12 oder PEM → SecIdentity (eigener Mini-DER-Parser)
    LocalService.swift         actor; SQLite; Backup-Export/-Import
    SQLite.swift               dünner C-API-Wrapper
    OfflineService.swift       @Observable @MainActor; Lesecache + Warteschlange
    OfflineQueue.swift         persistente Queue je `trink:<mode>|<baseUrl>`
    ServiceFactory.swift       createConfiguredEntryService(settings, offlineFaehig:)
    TrinkError.swift           TrinkErrorKind + neverSent + isPermanent
    TrinkValidation.swift      Grenzen wie der Server (Getränk ≤60, Menge 1–10000, Ziel 0–20000, Name ≤50)
  State/AppStore.swift         @Observable @MainActor; baut den Dienst aus den Settings, lädt alles, `run { }`
  Theme/MhTheme.swift          Minze & Honig 2.0: Rollen hell/dunkel (`Mh.*`), Radien, Abstände, Figtree, `.mhText(…)`
  Theme/MhBausteine.swift      Bausteine des Designsystems (MhKopf, Buttons, MhSegmente, MhAuswahl, MhHinweis …)
  Views/                       RootView (Kopf + Segmente Heute|Statistik, NavigationStack) · HomeView · StatsView
                               · NutzerView · SettingsView · Dialogs · Components (app-eigene Bausteine)
  Debug/Bildschirmfotodaten.swift  nur Debug: erfundene Testdaten für die Bildschirmfotos
  Fonts/                       Figtree-Regular/-Medium/-SemiBold.ttf (Lizenz: licenses/Figtree-OFL.txt)
  Assets.xcassets/             AppIcon (light/dark/tinted 1024), AccentColor, LaunchBackground, Mh*-Liniensymbole
Config/TrinkTracker-Info.plist bewusst außerhalb des Sync-Ordners (UIAppFonts, UIFileSharingEnabled …)
Design/                        Icon-Quelle: generate_app_icons.swift + SVG-Vorschauen (nicht im Build)
TrinkTrackerTests/             Swift Testing; FakeService als Server-Attrappe
TrinkTrackerUITests/           XCUITest `ScreenshotTests` (nur für den Workflow „Bildschirmfotos“)
.github/workflows/             ci.yml (Build + Unit-Tests + Release-Build), screenshots.yml (Bildschirmfotos)
```

**Sync-Gruppen:** `TrinkTracker/`, `TrinkTrackerTests/` und `TrinkTrackerUITests/` sind
`PBXFileSystemSynchronizedRootGroup`. Neue Dateien einfach in den Ordner legen —
`project.pbxproj` **nicht** von Hand um Dateireferenzen ergänzen.

### Datenfluss

`AppSettings` → `createConfiguredEntryService` → (`LocalService` | `OfflineService(inner: APIService)`)
→ `AppStore` → Views. Der Store baut den Dienst neu, sobald sich die Signatur
(Modus, URL, Key, CF-Token, Cert-Ordner, Server-Actions) ändert; die UI meldet
Änderungen über `store.settingsChanged()` (SettingsView beobachtet `settings.revision`).

`AppStore.run { service in … }` führt eine Schreibaktion aus, lädt neu und
liefert `nil` (Erfolg) oder die Fehlermeldung. Views geben das an
`ToastCenter.result(error, success:)`.

---

## 4. Regeln, die nicht verhandelbar sind

1. **Keine Geheimnisse im Repo.** Keine URLs, Keys, Tokens, Zertifikate,
   Familiendaten — nicht in Code, Tests, Doku, Screenshots oder Commits.
   `*.p12 *.pem *.crt *.key` stehen in `.gitignore`.
2. **Offline-Regel (Spec 3.1):** In die Warteschlange darf nur eine Schreibaktion,
   die den Server **nachweislich nie erreicht hat** (`TrinkError.neverSent == true`:
   kein Netz, Host/DNS nicht erreichbar, TLS-Handshake). Timeout oder Abbruch
   *während* der Übertragung → Fehler melden, **nicht** einreihen (Doppel-Anlage).
   Nutzer-/Favoritenverwaltung wird nie eingereiht.
3. **Queue-Kennung** ist `trink:<mode>|<baseUrl>`. Getrennte Queues je Modus und URL;
   ein URL-Wechsel legt eine neue an, die alte bleibt liegen.
4. **Zeit:** Server speichert UTC ohne Zonensuffix, Tagesgrenzen gelten in
   Europe/Berlin. Immer `BerlinTime` verwenden, nie `Calendar.current`/Gerätezone.
   `create_time` an den Server: `yyyy-MM-dd'T'HH:mm` Berliner Zeit (`BerlinTime.formatCreateTime`).
5. **Formate bleiben kompatibel** (Abschnitt 6): SQLite-Zeitformat
   `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, Backup-JSON, Settings-Schlüssel.
6. **Cloudflare-Diagnosen** unverändert: 3xx auf `*.cloudflareaccess.com` →
   `cloudflareLogin`; 403 mit `cf-ray` → `cloudflarePolicy`. Redirects niemals folgen.
7. **API-Key optional** in mTLS und Cloudflare: leer ⇒ **kein** `X-API-Key`-Header.
8. **Nutzer-/Favoritenverwaltung in Server-Modi** nur, wenn
   `serverUserManagement` an ist (Spec 2.2 Option A: `nutzer_anlegen`,
   `nutzer_umbenennen`, `nutzer_loeschen`, `favorit_loeschen`). Sonst UI ausblenden
   **und erklären**, warum (nicht stumm weglassen).
9. **Zahlen in der UI ohne Tausendertrennzeichen** („1500 ml“, nicht „1.500 ml“).
   Bei Interpolation von Ints in `Text` deshalb `Text(verbatim:)` oder String vorformatieren.
10. **Kein Seeding.** Erststart = lokaler Modus, leer.

---

## 5. Design „Minze & Honig 2.0“

Maßgeblich ist der Design Guide „Minze & Honig 2.0“ (Rollen, Typo, Komponenten);
die Web-App ist die Referenz für Aufbau und Wirkung. Alles Gestalterische steht
in `Theme/MhTheme.swift` (Rollen) und `Theme/MhBausteine.swift` (Bausteine) —
Views benutzen nur Rollen (`Mh.primary`, `Mh.textSecondary` …), nie Hex- oder
Skalenwerte.

* **Farbe ist Signal, keine Fläche:** keine Pastell-Buttons, -Kacheln oder
  -Karten. Pastell nur als Punkt (`MhPunkt`), 4-pt-Balken (`MhBalken`),
  gewählte Option (`MhAuswahl`) oder Hinweis (`MhHinweis`). Datenfarben
  `Mh.data1/2/3` immer mit Zahl oder Text daneben.
* **Genau eine Hauptaktion je Ansicht** (`.mhHaupt` / `MhHauptButtonStil`):
  Heute „Eintrag anlegen“, Nutzer „Nutzer anlegen“, Einstellungen „Verbindung
  testen“ (Server) bzw. „Exportieren“ (lokal). Alles andere `.mhZweit`
  (Haarlinie), `.mhText` oder `.mhLoeschen` (Löschen, Rückgängig).
* **Haarlinien und Weißraum** (`MhTrennlinie`, `Abschnittskopf`) statt Karten.
* **Figtree** nur 400/500/600 über `.mhText(.h1)` usw. (Dynamic Type inklusive),
  keine Kursive. Große Zahlen dünn (`.number`) in Textfarbe, Einheit klein.
* **Liniensymbole** `Mh*.imageset` über `MhSymbol`/`MhSymbolButton` statt SF
  Symbols und Emojis. Nicht benutzte Symbole entfernen (Bausatz-Skript).
* **Dunkelmodus** über die Rollen (Grund `#1F2221`, Flächen `#262A28`, Linien
  `#343A36`, farbiger Text nur aus den 200/300-Stufen). Folgt dem System.
* Touch-Ziele mindestens 44 pt (`Mh.touch`).
* Gerüst wie im Web: Kopf „Trink-Tracker“ mit Symbol-Knöpfen (Nutzer,
  Einstellungen — immer erreichbar, auch ohne Verbindung), Segmentschalter
  Heute | Statistik; Nutzer und Einstellungen sind Unterseiten
  (`Unterseitenrahmen`, Zurück über die Navigationsleiste).
* App-eigene Bausteine in `Views/Components.swift`: `Abschnittskopf`,
  `FeldLabel`, `Hinweistext`, `AuswahlZeile`, `OfflineBanner`,
  `TrinkTextField`, `FlowLayout`, Toast. Erst diese und die Mh-Bausteine
  nutzen, bevor neue entstehen.

---

## 6. Kompatibilität zur früheren Flutter-App

Die Flutter-App lief unter **derselben Bundle-ID**; eine Installation der
nativen App ersetzt sie und übernimmt ihre Daten. Das darf nicht brechen:

| Was | Wo / Wie |
|---|---|
| Lokale DB | `Documents/trinktracker.db`, Tabellen `users`, `entries`, `favoriten`, `PRAGMA user_version = 1` |
| Zeitstempel in DB/Cache | `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` (`iso8601String`) — Stringvergleiche in SQL hängen daran |
| Backup-JSON | `{ schema, exported_at, users[], entries[], favoriten[] }`, beidseitig lesbar |
| Settings-Schlüssel | `trinktracker_settings.<key>`; Flutter schrieb `flutter.trinktracker_settings.<key>` — einmalige Migration in `LegacyFlutterMigration` (Marker `trinktracker.native.migratedFromFlutter`) |
| Keys | Keychain generic password, Account = Schlüsselname; Migration probiert Service = Bundle-ID / `flutter_secure_storage_service` |
| Queue / Cache | `trinktracker.queue.<queueKey>`, `trinktracker.cache.<queueKey>|<name>`; Flutter-Präfix `flutter.` wird beim ersten Lesen übernommen |
| Modus-Schlüssel | `demo`, `apiKey`, `api`, `cloudflare` (rawValue von `ConnectionMode`) |

---

## 7. Entscheidungen aus dem Port (Chronik, Sept. 2026)

1. **Port statt Neubau:** Struktur, Namen, Kommentare und Tests 1:1 aus Dart übernommen,
   damit die Spec-Verweise weiter stimmen.
2. **iOS 17 Minimum**, `@Observable` statt Combine/ObservableObject.
3. **Bundle-ID beibehalten** (Ersatz der Flutter-App, Datenübernahme) statt parallel installieren.
4. **SQLite direkt** (kein SwiftData/CoreData), um DB-Datei und Backups kompatibel zu halten.
5. **BerlinTime manuell** (EU-Regel) statt `TimeZone("Europe/Berlin")`, damit die
   Tests identisch bleiben und die Logik zur Server-Implementierung passt.
6. **mTLS:** `client.p12` ergänzt (robust, Passwort im Keychain), PEM-Weg
   beibehalten (PKCS#8/PKCS#1/SEC1 → Keychain → Identity). **Auf echtem Mandanten
   noch nicht verifiziert.**
7. **Favoriten löschen** sichtbar gemacht: Kontextmenü auf den Chips (gedrückt halten),
   Sektion „Favoriten von <Nutzer>“ in den Einstellungen immer sichtbar, Hinweistexte.
   Vorher hing es an einem stillen Long-Press → als nicht auffindbar gemeldet.
8. **Standardnutzer je Gerät (★):** `defaultUserId` lokal in UserDefaults, greift
   einmal je App-Start (`AppStore.defaultUserApplied`), danach freier Wechsel.
   Nicht auf dem Server, weil jedes Telefon seinen eigenen Standard hat.
9. **„Undo“ → „Rückgängig“** (einziger englischer UI-Begriff).
10. **Charts:** 7-Tage-Achse nutzt Wochentagskürzel direkt als X-Wert; eigener
    `AxisValueLabel`-Inhalt löste eine Charts-Warnung aus.
11. **Version 1.3.0 (Build 1)** als `MARKETING_VERSION` im Target; Flutter stand bei 1.2.0.
    Major/Minor über Plattformen synchron (Spec 8), Patch darf divergieren.
12. **Info.plist liegt in `Config/`**, nicht im Sync-Ordner, damit sie nicht als
    Ressource kopiert wird. `GENERATE_INFOPLIST_FILE = NO`.
13. **Minze & Honig 2.0 (Nov. 2026):** Figtree statt Nunito, Rollen statt
    Palette, Liniensymbole statt SF Symbols. Tab-Leiste ersetzt durch Kopf mit
    Segmentschalter Heute | Statistik wie im Web; Nutzerverwaltung als eigene
    Unterseite „Nutzer“ (vorher in den Einstellungen), Tagesziel/Umbenennen/
    Löschen je Nutzer im Menü „…“. Funktionen, Datenformate und Texte der
    Meldungen im Kern unverändert.

---

## 8. Offen (siehe auch GOTO.md)

* Remote: `git@github.com:benjcas451/TrinkTracker-XCode.git` (Branch `main`).
* mTLS (p12 und PEM), Cloudflare-Diagnosen und Offline-Doppel-Anlage gegen einen
  **Testmandanten** verifizieren.
* watchOS-Target mit `WatchConnectivity`, eigener Outbox (nicht `OfflineService`
  wiederverwenden) und Komplikationen (Spec 6).
* Apple Health (opt-in, nur Wasser), Signing/TestFlight. CI läuft über GitHub
  Actions (`ci.yml`: Build, Unit-Tests, Release-Build; `screenshots.yml`:
  Bildschirmfotos hell/dunkel, normale und große Schrift).
* App-Icon: aqua-blau vs. App-Grün — bewusste Entscheidung steht aus.
  Neu erzeugen mit `swift Design/generate_app_icons.swift` (Farben in `palettes`).
* Optional: Swift-6-Sprachmodus einschalten.

---

## 9. Arbeitsweise für Agenten

* Vor Änderungen an Services die Tests in `TrinkTrackerTests/` lesen — sie
  kodieren die Spec-Regeln (Offline, Berlin-Zeit, Validierung, Settings-Slots).
* Neue Regel/Feature ⇒ Test dazu. `FakeService` (überschreibbar, `class`) ist die
  Server-Attrappe; `freshDefaults()` liefert isolierte UserDefaults.
* UI-Änderungen im Simulator per Screenshot in **Light und Dark** prüfen.
* Kleine, fokussierte Commits mit deutscher Message. Nichts committen, was nach
  URL, Key, Token oder Zertifikat aussieht.
* README.md und diese Datei aktuell halten, wenn sich Architektur oder Regeln ändern.
