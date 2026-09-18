import Foundation

/// Oberste Ebene der Verbindungswahl: lokale Datenbank oder Server-API. Womit
/// sich die App gegenüber der API ausweist, steht eine Ebene darunter als
/// `ConnectionMode`.
enum ConnectionKind: String, CaseIterable, Identifiable, Sendable {
    case local
    case api

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Lokal (SQLite)"
        case .api: return "API"
        }
    }
}

/// Die vier Verbindungsmodi (Spec 3). Der gespeicherte Key ist identisch zu den
/// anderen Apps, damit Einstellungen und Doku über die Plattformen passen.
enum ConnectionMode: String, CaseIterable, Identifiable, Sendable {
    case demo
    case apiKey
    case api
    case cloudflare

    var id: String { rawValue }

    /// Gespeicherter Schlüssel (identisch zur Flutter-App).
    var key: String { rawValue }

    /// Vollständige Bezeichnung, etwa für die Info-Zeile.
    var label: String {
        switch self {
        case .demo: return "Lokal (SQLite)"
        case .apiKey: return "Server (API-Key)"
        case .api: return "Server (mTLS, optional + API-Key)"
        case .cloudflare: return "Server (Cloudflare Access)"
        }
    }

    /// Kurzform ohne „Server"-Präfix für die Auswahl unterhalb von „API".
    var authLabel: String {
        switch self {
        case .demo: return ""
        case .apiKey: return "API-Key"
        case .api: return "mTLS (optional + API-Key)"
        case .cloudflare: return "Cloudflare Access"
        }
    }

    var isServer: Bool { self != .demo }

    var kind: ConnectionKind { isServer ? .api : .local }

    /// Die Authentifizierungsarten der API, in der Reihenfolge der Anzeige.
    static let authModes: [ConnectionMode] = [.apiKey, .api, .cloudflare]

    /// Womit die API-Auswahl startet, wenn vorher „Lokal" eingestellt war.
    static let defaultAuthMode: ConnectionMode = .apiKey

    static func fromKey(_ key: String?) -> ConnectionMode {
        key.flatMap(ConnectionMode.init(rawValue:)) ?? .demo
    }
}
