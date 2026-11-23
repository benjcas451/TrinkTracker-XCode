# GoTo: Nächste Schritte zu Hause

Einstiegspunkt für die Arbeiten, die echte Geräte, einen Testmandanten oder
private Zugangsdaten benötigen. Zugangsdaten, Hostnamen, Zertifikate und
Familien-Daten bleiben ausschließlich lokal und werden **nicht** committed.

## Stand

* Native SwiftUI-App, portiert aus `TrinkTracker-Flutter`. Alle Screens,
  Modi, Offline-Logik und Tests sind übernommen.
* Build und Unit-Tests laufen im iOS-Simulator (Xcode 27).
* Gleiche Bundle-ID wie die Flutter-App: eine Installation ersetzt die alte App
  und übernimmt lokale Datenbank, Einstellungen und Keys.

## 1. Repository

- [x] Repository angelegt und nach `github.com/benjcas451/TrinkTracker-XCode`
      gepusht (Branch `main`).
- [ ] Vor jedem Push `git status --short` gegenlesen: keine URLs, Keys, Tokens,
      Zertifikate oder Nutzerdaten im Diff.

## 2. Auf dem iPhone starten

- [ ] Projekt in Xcode öffnen, Signing prüfen (Team wird automatisch gesetzt).
- [ ] Erststart auf einem Gerät **ohne** vorherige Flutter-Installation:
      lokaler Modus, keine Nutzer, keine URL, keine Keys.
- [ ] Erststart auf einem Gerät **mit** Flutter-Installation: Nutzer, Einträge,
      Modus, URLs und Keys sind da; ggf. wartende Queue wird gesendet.
- [ ] App-Icon in Light, Dark und Tinted kontrollieren.
- [ ] Dynamic Type auf größter Stufe durchklicken (Chips, Karten, Statistik).

## 3. Datei-Import prüfen

Der Dateidialog liefert Security-Scoped-URLs; gelesen werden die Bytes.

- [ ] Im lokalen Modus **Exportieren** → „In Dateien sichern".
- [ ] Bestand ändern, dieselbe Datei über **Importieren** zurückspielen und
      prüfen, dass der alte Stand vollständig zurückkommt.
- [ ] Ein Backup aus der Flutter-App importieren (und umgekehrt).
- [ ] Datei aus iCloud Drive statt lokalem Speicher wählen.

## 4. Mit einem Testmandanten validieren

Nur Testdaten verwenden; keine produktiven Werte in Screenshots oder Logs.

- [ ] Basis-URL eintragen und **Verbindung testen**.
- [ ] API-Key gegen den Testmandanten prüfen.
- [ ] **mTLS mit `client.p12`**: importieren, Passwort eingeben, Verbindung
      testen. Danach App beenden und erneut testen (Passwort aus dem
      Schlüsselbund).
- [ ] **mTLS mit PEM** (`client.crt` + `client.key`): RSA-Schlüssel (PKCS#8 und
      PKCS#1) sowie EC-Schlüssel je einmal probieren. Schlägt die Verknüpfung
      im Schlüsselbund fehl, meldet die App das und verweist auf p12.
- [ ] mTLS einmal ohne und einmal mit optionalem API-Key.
- [ ] Cloudflare Access mit zugewiesenem Service Token; Diagnosen prüfen:
      Login-Redirect bei ungültigem Token, Richtlinienhinweis bei `403` +
      `cf-ray`.
- [ ] Offline-Test: Flugmodus, Eintrag anlegen (erscheint mit „wartet auf
      Übertragung"), Netz an, App in den Vordergrund → genau ein Eintrag.
- [ ] Timeout mit unklarem Ausgang simulieren (z. B. Proxy, der die Antwort
      verschluckt): Fehler wird gemeldet, **kein** Eintrag in der Queue.

## 5. Offene Entscheidungen

- [ ] App-Icon: aqua-blau vs. App-Grün. Quelle liegt jetzt hier:
      `swift Design/generate_app_icons.swift`, Farben im Skript unter `palettes`.
- [ ] Die vier optionalen Server-Actions für Nutzer-/Favoritenverwaltung:
      Option A oder B je Mandant.
- [ ] Swift-6-Sprachmodus: aktuell `SWIFT_VERSION = 5.0`; die verbleibenden
      Concurrency-Warnungen sind klein und gut umstellbar.

## 6. Noch offene Punkte der Produktspezifikation

- [ ] watchOS-Target samt `WatchConnectivity`, eigener Outbox und
      Komplikationen (Spec 6).
- [ ] Apple-Health-Synchronisierung nur für Wasser, opt-in — oder bewusst
      zurückstellen.
- [x] CI: GitHub Actions (`ci.yml` Build + Unit-Tests, `screenshots.yml` Bildschirmfotos).
- [ ] Signing: TestFlight-Verteilung.
- [ ] Cloudflare-Service-Token bzw. Bypass-Regel je Familien-Host außerhalb des
      Repositories konfigurieren.

## Vor jedem Push

- [ ] `git status --short` ist leer.
- [ ] Keine URLs, Keys, Tokens, Zertifikate oder Nutzerdaten im Diff.
- [ ] `xcodebuild … test` läuft durch.
