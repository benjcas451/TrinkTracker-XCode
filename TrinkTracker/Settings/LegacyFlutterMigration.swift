import Foundation
import Security

/// Übernimmt beim ersten Start die Einstellungen der Flutter-Version dieser
/// App, falls sie auf dem Gerät installiert war (gleiche Bundle-ID):
/// shared_preferences schreibt `flutter.<key>` in die UserDefaults,
/// flutter_secure_storage generische Passwörter mit Account = Schlüsselname.
///
/// Die lokale SQLite-Datenbank liegt an derselben Stelle (`Documents/
/// trinktracker.db`) und wird ohne Migration weiterverwendet.
enum LegacyFlutterMigration {
    static let markerKey = "trinktracker.native.migratedFromFlutter"

    @MainActor
    static func runIfNeeded(defaults: UserDefaults, keychain: KeychainStore) {
        if defaults.bool(forKey: markerKey) { return }
        defer { defaults.set(true, forKey: markerKey) }

        let prefix = "flutter." + AppSettings.prefsPrefix
        let hasLegacy = defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(prefix) }
        guard hasLegacy else { return }

        for key in [AppSettings.keyMode, AppSettings.keyApiBaseUrl, AppSettings.keyApiKeyBaseUrl,
                    AppSettings.keyCloudflareBaseUrl, AppSettings.keyCertFolder] {
            if let value = defaults.string(forKey: prefix + key), defaults.object(forKey: AppSettings.prefsPrefix + key) == nil {
                defaults.set(value, forKey: AppSettings.prefsPrefix + key)
            }
        }
        if let selected = defaults.object(forKey: prefix + AppSettings.keySelectedUser) as? Int,
           defaults.object(forKey: AppSettings.prefsPrefix + AppSettings.keySelectedUser) == nil {
            defaults.set(selected, forKey: AppSettings.prefsPrefix + AppSettings.keySelectedUser)
        }
        if let management = defaults.object(forKey: prefix + AppSettings.keyServerUserManagement) as? Bool,
           defaults.object(forKey: AppSettings.prefsPrefix + AppSettings.keyServerUserManagement) == nil {
            defaults.set(management, forKey: AppSettings.prefsPrefix + AppSettings.keyServerUserManagement)
        }

        for key in [AppSettings.keyApiKey, AppSettings.keyMtlsApiKey, AppSettings.keyCloudflareApiKey,
                    AppSettings.keyCfAccessClientId, AppSettings.keyCfAccessClientSecret] {
            if keychain.read(key) == nil, let legacy = legacySecret(account: key) {
                keychain.write(key, legacy)
            }
        }
    }

    /// flutter_secure_storage: kSecClassGenericPassword, Account = Schlüssel,
    /// Service je nach Version Bundle-ID oder fester Name — beides probieren.
    private static func legacySecret(account: String) -> String? {
        let services: [String?] = [Bundle.main.bundleIdentifier, "flutter_secure_storage_service", nil]
        for service in services {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if let service { query[kSecAttrService as String] = service }
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
