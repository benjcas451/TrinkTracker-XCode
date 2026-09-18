import Foundation
import Observation

/// Einstellungen mit getrennten Slots je Modus (Spec 3.2), damit ein
/// Moduswechsel nichts überschreibt.
///
/// **Alle Verbindungsfelder starten leer.** Es gibt keinen Default-Host, keinen
/// Default-Key und keine vordefinierten Nutzer — auch nicht in Debug-Builds
/// (Spec 1, 3.2, 9.2).
@Observable
@MainActor
final class AppSettings {
    static let prefsPrefix = "trinktracker_settings."

    // Schlüsselnamen identisch zur Flutter-App (Spec 3.2).
    static let keyMode = "mode"
    static let keyApiBaseUrl = "apiBaseUrl"
    static let keyApiKeyBaseUrl = "apiKeyBaseUrl"
    static let keyCloudflareBaseUrl = "cloudflareBaseUrl"
    static let keyApiKey = "apiKey"
    static let keyMtlsApiKey = "mtlsApiKey"
    static let keyCloudflareApiKey = "cloudflareApiKey"
    static let keyCfAccessClientId = "cfAccessClientId"
    static let keyCfAccessClientSecret = "cfAccessClientSecret"
    static let keyCertFolder = "certFolder"
    static let keySelectedUser = "selectedUserId"
    static let keyDefaultUser = "defaultUserId"
    static let keyServerUserManagement = "serverUserManagement"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore

    private(set) var mode: ConnectionMode = .demo
    private(set) var apiBaseUrl = ""
    private(set) var apiKeyBaseUrl = ""
    private(set) var cloudflareBaseUrl = ""
    private(set) var apiKey = ""
    private(set) var mtlsApiKey = ""
    private(set) var cloudflareApiKey = ""
    private(set) var cfAccessClientId = ""
    private(set) var cfAccessClientSecret = ""
    private(set) var certFolder = ""
    private(set) var selectedUserId: Int?

    /// Standardnutzer **dieses Geräts** („dieses iPhone gehört Mia“): Mit ihm
    /// startet die App, egal für wen zuletzt eingetragen wurde. Rein lokal,
    /// wird nicht mit dem Server geteilt.
    private(set) var defaultUserId: Int?

    /// Nutzer-/Favoritenverwaltung in Server-Modi — nur einschalten, wenn der
    /// Mandant die vier Zusatz-Actions aus Spec 2.2 Option A installiert hat.
    private(set) var serverUserManagement = false

    /// Zählt jede gespeicherte Änderung; der Store baut daraus die Signatur.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore(), migrateLegacy: Bool = true) {
        self.defaults = defaults
        self.keychain = keychain
        if migrateLegacy {
            LegacyFlutterMigration.runIfNeeded(defaults: defaults, keychain: keychain)
        }
        load()
    }

    private func read(_ key: String) -> String {
        defaults.string(forKey: Self.prefsPrefix + key) ?? ""
    }

    private func load() {
        mode = ConnectionMode.fromKey(read(Self.keyMode))
        apiBaseUrl = read(Self.keyApiBaseUrl)
        apiKeyBaseUrl = read(Self.keyApiKeyBaseUrl)
        cloudflareBaseUrl = read(Self.keyCloudflareBaseUrl)
        certFolder = read(Self.keyCertFolder)
        selectedUserId = defaults.object(forKey: Self.prefsPrefix + Self.keySelectedUser) as? Int
        defaultUserId = defaults.object(forKey: Self.prefsPrefix + Self.keyDefaultUser) as? Int
        serverUserManagement = defaults.bool(forKey: Self.prefsPrefix + Self.keyServerUserManagement)

        apiKey = keychain.read(Self.keyApiKey) ?? ""
        mtlsApiKey = keychain.read(Self.keyMtlsApiKey) ?? ""
        cloudflareApiKey = keychain.read(Self.keyCloudflareApiKey) ?? ""
        cfAccessClientId = keychain.read(Self.keyCfAccessClientId) ?? ""
        cfAccessClientSecret = keychain.read(Self.keyCfAccessClientSecret) ?? ""
    }

    private func putString(_ key: String, _ value: String) {
        defaults.set(value, forKey: Self.prefsPrefix + key)
        revision += 1
    }

    private func putSecret(_ key: String, _ value: String) {
        keychain.write(key, value)
        revision += 1
    }

    /// Basis-URL des Modus — Pflegefeld, initial leer (Spec 3.2).
    func baseUrl(for mode: ConnectionMode) -> String {
        switch mode {
        case .demo: return ""
        case .api: return apiBaseUrl
        case .apiKey: return apiKeyBaseUrl
        case .cloudflare: return cloudflareBaseUrl
        }
    }

    /// API-Key des Modus. Im mTLS- und Cloudflare-Modus optional: ist er leer,
    /// wird **kein** `X-API-Key`-Header gesendet (Spec 3.3).
    func apiKey(for mode: ConnectionMode) -> String {
        switch mode {
        case .demo: return ""
        case .api: return mtlsApiKey
        case .apiKey: return apiKey
        case .cloudflare: return cloudflareApiKey
        }
    }

    var activeBaseUrl: String { baseUrl(for: mode) }
    var activeApiKey: String { apiKey(for: mode) }

    /// Kennung der Offline-Warteschlange (Spec 3.1): Modi und URLs haben
    /// getrennte Queues, ein URL-Wechsel erzeugt eine neue — die alte bleibt
    /// unberührt und läuft nach einem Rückwechsel weiter.
    var queueKey: String { "trink:\(mode.key)|\(activeBaseUrl)" }

    func setMode(_ newMode: ConnectionMode) {
        if mode == newMode { return }
        mode = newMode
        putString(Self.keyMode, newMode.key)
    }

    func setBaseUrl(_ mode: ConnectionMode, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .demo:
            return
        case .api:
            if apiBaseUrl == trimmed { return }
            apiBaseUrl = trimmed
            putString(Self.keyApiBaseUrl, trimmed)
        case .apiKey:
            if apiKeyBaseUrl == trimmed { return }
            apiKeyBaseUrl = trimmed
            putString(Self.keyApiKeyBaseUrl, trimmed)
        case .cloudflare:
            if cloudflareBaseUrl == trimmed { return }
            cloudflareBaseUrl = trimmed
            putString(Self.keyCloudflareBaseUrl, trimmed)
        }
    }

    func setApiKey(_ mode: ConnectionMode, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .demo:
            return
        case .api:
            if mtlsApiKey == trimmed { return }
            mtlsApiKey = trimmed
            putSecret(Self.keyMtlsApiKey, trimmed)
        case .apiKey:
            if apiKey == trimmed { return }
            apiKey = trimmed
            putSecret(Self.keyApiKey, trimmed)
        case .cloudflare:
            if cloudflareApiKey == trimmed { return }
            cloudflareApiKey = trimmed
            putSecret(Self.keyCloudflareApiKey, trimmed)
        }
    }

    func setCfAccessClientId(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cfAccessClientId == trimmed { return }
        cfAccessClientId = trimmed
        putSecret(Self.keyCfAccessClientId, trimmed)
    }

    func setCfAccessClientSecret(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cfAccessClientSecret == trimmed { return }
        cfAccessClientSecret = trimmed
        putSecret(Self.keyCfAccessClientSecret, trimmed)
    }

    func setCertFolder(_ value: String) {
        if certFolder == value { return }
        certFolder = value
        putString(Self.keyCertFolder, value)
    }

    func setSelectedUserId(_ userId: Int?) {
        if selectedUserId == userId { return }
        selectedUserId = userId
        if let userId {
            defaults.set(userId, forKey: Self.prefsPrefix + Self.keySelectedUser)
        } else {
            defaults.removeObject(forKey: Self.prefsPrefix + Self.keySelectedUser)
        }
    }

    func setDefaultUserId(_ userId: Int?) {
        if defaultUserId == userId { return }
        defaultUserId = userId
        if let userId {
            defaults.set(userId, forKey: Self.prefsPrefix + Self.keyDefaultUser)
        } else {
            defaults.removeObject(forKey: Self.prefsPrefix + Self.keyDefaultUser)
        }
    }

    func setServerUserManagement(_ value: Bool) {
        if serverUserManagement == value { return }
        serverUserManagement = value
        defaults.set(value, forKey: Self.prefsPrefix + Self.keyServerUserManagement)
        revision += 1
    }
}

/// Prüft eine eingegebene Basis-URL: getrimmt, nur `https://`, mit Host.
/// Liefert `nil`, wenn die Eingabe brauchbar ist, sonst den Fehlertext.
func validateBaseUrl(_ input: String) -> String? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "Basis-URL fehlt." }
    guard let components = URLComponents(string: value), let scheme = components.scheme, !scheme.isEmpty else {
        return "Keine gültige URL."
    }
    if scheme.lowercased() != "https" { return "Nur https:// ist erlaubt." }
    if (components.host ?? "").isEmpty { return "Der Host fehlt." }
    return nil
}

/// Platzhalter für die Base-URL-Felder — nur ein Formathinweis, kein Default
/// (Spec 3.2).
let baseUrlPlaceholder = "https://…/trink-tracker/api.php"
