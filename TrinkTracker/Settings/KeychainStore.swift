import Foundation
import Security

/// Kleiner Ersatz für flutter_secure_storage: generische Passwörter im
/// Schlüsselbund der App, ein Eintrag je Schlüssel.
struct KeychainStore: Sendable {
    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "trinktracker") + ".settings") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Leerer Wert löscht den Eintrag. Fehler werden verschluckt: ohne
    /// erreichbaren Schlüsselbund bleibt der Wert für die Sitzung im Speicher.
    func write(_ key: String, _ value: String) {
        if value.isEmpty {
            SecItemDelete(baseQuery(key) as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
