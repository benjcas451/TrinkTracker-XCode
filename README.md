# Trink-Tracker (iOS, nativ)

Getränke tracken für die ganze Familie — offline-fähig, mandantenneutral.
Native SwiftUI-Umsetzung der App-Spezifikation v1.2, portiert aus der
Flutter-Codebasis (`TrinkTracker-Flutter`). Gleiche Bundle-ID, gleiches
Datenmodell, gleiche Backups.

> **Mandantenneutral:** Die App enthält **keine** vordefinierte URL, keinen
> vordefinierten Key und keine vordefinierten Nutzer. Jede Familie trägt Host
> und Zugangsdaten selbst in den Einstellungen ein — auch in Debug-Builds.

## Funktionsumfang

| Bereich | Stand |
|---|---|
| Vier Verbindungsmodi (Lokal/SQLite · API-Key · mTLS · Cloudflare Access) | ✅ |
| Getrennte Base-URL-/Key-Slots je Modus, „Verbindung testen" | ✅ |
| Offline-Wrapper: Lesecache + Warteschlange ohne Doppel-Anlage | ✅ |
| Heute: Tagesmengen der Familie, Schnellwahl, klassische Größen, Rückgängig | ✅ |
| Standardnutzer je Gerät (★), Favoriten per Kontextmenü löschen | ✅ — nur in der nativen App |
| Statistik: 7-Tage-Balken, 30-Tage-Linie, Ziel-Linie (Swift Charts) | ✅ |
| Einstellungen: Nutzer, Tagesziele, Favoriten, Backup/Export, Zertifikate | ✅ |
| Design „Minze & Honig 2.0“ inkl. Dark Mode, Figtree gebundelt, Dynamic Type | ✅ |
| Übernahme von Einstellungen und lokaler DB aus der Flutter-Version | ✅ |
| mTLS: `client.p12` **oder** `client.crt` + `client.key` (PEM) | ✅ — auf echtem Mandanten ungetestet |
| Watch (watchOS), Komplikationen, Apple Health | ⛔ offen — siehe unten |
| CI (GitHub Actions: Build, Unit-Tests, Bildschirmfotos) | ✅ |
| Signing/TestFlight | ⛔ offen |

## Version

**1.3.0** (Build 1) — erste native Ausgabe. Gegenüber der Flutter-App 1.2.0
neu: Standardnutzer je Gerät, Favoriten per Kontextmenü löschen, p12-Import
für mTLS, Übernahme von Flutter-Daten und -Einstellungen. Major/Minor gilt
über alle Plattformen (Spec 8), Patch darf divergieren. Die Version steht als
`MARKETING_VERSION` im Target, nicht in der Info.plist.

## Voraussetzungen

* Xcode 27, iOS 17.0 oder neuer.
* Keine externen Abhängigkeiten — nur System-Frameworks (SwiftUI, Charts,
  Observation, Security, SQLite3, UniformTypeIdentifiers).

## Aufbau

```
TrinkTracker/
  TrinkTrackerApp.swift        Einstieg, Environment (Settings, Store, Toasts)
  Models/Models.swift          Datenmodell + tolerantes JSON-Parsen
  Util/BerlinTime.swift        Europe/Berlin ohne Zeitzonen-Datenbank
  Settings/
    ConnectionMode.swift       Lokal · API-Key · mTLS · Cloudflare
    AppSettings.swift          Modus, URLs, Keys (UserDefaults + Schlüsselbund)
    KeychainStore.swift        Ersatz für flutter_secure_storage
    LegacyFlutterMigration.swift  Einmalige Übernahme der Flutter-Einstellungen
  Services/
    TrinkEntryService.swift    Protokoll über alle Modi
    APIService.swift           Server (API-Key / mTLS / Cloudflare), URLSession
    ClientCertificateStore.swift  p12 oder PEM → SecIdentity
    LocalService.swift         Lokaler Modus (SQLite-Actor) + Backup-JSON
    SQLite.swift               Dünner Wrapper um die C-API
    OfflineService.swift       Lesecache + Warteschlange
    OfflineQueue.swift         Persistente Queue je „trink:<mode>|<baseUrl>"
    ServiceFactory.swift       createConfiguredEntryService(...)
    TrinkError.swift, TrinkValidation.swift
  State/AppStore.swift         Bindeglied zur UI (@Observable, @MainActor)
  Theme/MhTheme.swift          Minze & Honig 2.0: Rollen, Figtree, Abstände
  Theme/MhBausteine.swift      Bausteine des Designsystems
  Views/                       Root · Heute · Statistik · Nutzer · Einstellungen · Dialoge
  Debug/                       Testdaten für Bildschirmfotos (nur Debug)
  Fonts/                       Figtree (Lizenz in licenses/)
  Assets.xcassets/             App-Icon (light/dark/tinted), Akzent, Launch, Liniensymbole
Config/TrinkTracker-Info.plist
Design/                        App-Icon-Generator + SVG-Vorschauen (nicht Teil des Builds)
TrinkTrackerTests/             Swift Testing: Berlin-Zeit, Modelle, Validierung,
                               Einstellungen, Offline-Queue, SQLite, PEM/DER
TrinkTrackerUITests/           ScreenshotTests (Bildschirmfotos im Workflow)
.github/workflows/             ci.yml, screenshots.yml
```

Die Ordner `TrinkTracker/`, `TrinkTrackerTests/` und `TrinkTrackerUITests/` sind **File System
Synchronized Groups**: Neue Swift-Dateien im Ordner sind automatisch im Target,
`project.pbxproj` muss dafür nicht angefasst werden.

### Verbindungsschicht

`createConfiguredEntryService(settings)` baut aus den Einstellungen den
passenden Dienst und legt in Server-Modi den `OfflineService` darüber. Für
„Verbindung testen" wird er mit `offlineFaehig: false` aufgerufen, damit der
echte Fehler sichtbar wird statt eines Cache-Treffers.

**Schreiben offline:** In die Warteschlange wandert eine Aktion nur, wenn sie
den Server nachweislich nie erreicht hat (`URLError`: kein Netz, Host nicht
erreichbar, DNS, TLS-Handshake). Ein Timeout oder Verbindungsabbruch *während*
der Übertragung meldet den Fehler und reiht **nicht** ein — sonst entstünde bei
einer angekommenen Anfrage eine Doppel-Anlage.

**Queue-Kennung** ist `trink:<mode>|<baseUrl>`. Modi und URLs haben damit
getrennte Warteschlangen; ein URL-Wechsel legt eine neue an und lässt die alte
unberührt, ein Rückwechsel nimmt sie wieder auf.

### Cloudflare-Diagnose

Redirects folgt die `URLSession` bewusst nicht (`willPerformHTTPRedirection`
→ `nil`), damit die Login-Seite als 3xx sichtbar bleibt:

* Redirect auf `*.cloudflareaccess.com` → „Service Token prüfen – möglicherweise
  abgelaufen."
* `403` mit `cf-ray` → „Token ist dieser Anwendung vermutlich nicht zugewiesen."

### mTLS

`ClientCertificateStore` sucht im gepflegten Ordner, sonst in
`Documents/certs` (über die Dateien-App erreichbar):

* **`client.p12`** (empfohlen): `SecPKCS12Import`, Passwort wird beim Import
  abgefragt und im Schlüsselbund gehalten.
* **`client.crt` + `client.key`** (PEM, wie in der Flutter-App): Zertifikat und
  Schlüssel werden in den Schlüsselbund gelegt und dort zu einer `SecIdentity`
  verknüpft. Unterstützt: PKCS#8, PKCS#1 (RSA) und SEC1 (EC), jeweils
  unverschlüsselt.

Beides ist gegen einen echten Mandanten noch nicht verifiziert — siehe
[`GOTO.md`](GOTO.md).

### Zeitzone

Tagesgrenzen rechnet der Server in Europe/Berlin. `Util/BerlinTime.swift`
bildet die EU-Sommerzeitregel direkt ab (letzter Sonntag im März/Oktober,
01:00 UTC) — unabhängig von der Gerätezone und 1:1 zur Flutter-Umsetzung,
damit die Tests identisch bleiben.

### Kompatibilität zur Flutter-Version

* **Lokale Datenbank:** gleiche Datei `Documents/trinktracker.db`, gleiches
  Schema, gleiches Zeitformat (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`). Eine bestehende
  Datenbank wird ohne Migration weiterverwendet.
* **Backups:** identisches JSON (`schema`, `users`, `entries`, `favoriten`),
  in beide Richtungen einspielbar.
* **Einstellungen:** Beim ersten Start werden `flutter.trinktracker_settings.*`
  aus den UserDefaults sowie die Keys aus dem Schlüsselbund übernommen; eine
  noch nicht gesendete Flutter-Warteschlange wird ebenfalls aufgenommen.

## Entwickeln

```bash
open TrinkTracker.xcodeproj
# oder auf der Kommandozeile:
xcodebuild -scheme TrinkTracker -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme TrinkTracker -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Signing: Team `2HNRMGYGMU`, Bundle-ID `org.dwarftsch.trinktracker`, automatisch.

## Noch offen

* **Watch:** Jetzt nativ möglich — watchOS-Target mit `WatchConnectivity`,
  eigener Outbox und Komplikationen (Spec 6). Der `OfflineService` wird dort
  bewusst nicht wiederverwendet.
* **Apple Health** (opt-in, nur Wasser).
* **Signing:** TestFlight-Verteilung (CI für Build und Tests läuft bereits).
* **Widgets / Live Activities** für die Schnellwahl (nicht in der Spec, liegt
  aber nahe).

## Keine Geheimnisse im Repo

Basis-URLs, API-Keys, Cloudflare-Tokens, Zertifikate und Familiendaten gehören
nicht in Code, Tests, CI oder Doku. `*.p12`, `*.pem`, `*.crt`, `*.key` sind in
`.gitignore` ausgeschlossen; Keys liegen im Schlüsselbund des Systems.
