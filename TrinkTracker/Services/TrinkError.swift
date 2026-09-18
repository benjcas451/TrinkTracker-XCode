import Foundation

/// Fehlerarten der Verbindungsschicht (Spec 3.3).
enum TrinkErrorKind: Sendable {
    /// Netzwerk/Transport — die Anfrage hat den Server nachweislich nie erreicht
    /// oder der Ausgang ist unklar (siehe `TrinkError.neverSent`).
    case network
    /// 401/403 ohne Cloudflare-Signatur — Key oder Zertifikat passt nicht.
    case auth
    /// Redirect auf *.cloudflareaccess.com: Access-Login-Seite statt API.
    case cloudflareLogin
    /// 403 mit `cf-ray`: Token erkannt, aber Richtlinie verweigert die Anwendung.
    case cloudflarePolicy
    /// 4xx mit Fehlermeldung des Servers (Validierung, Duplikat, nicht gefunden).
    case validation
    /// 5xx oder unlesbare Antwort.
    case server
    /// Konfiguration unvollständig (z. B. Basis-URL leer).
    case configuration
    /// Aktion wird im aktuellen Modus nicht unterstützt (Spec 2.2, Option B).
    case unsupported
}

struct TrinkError: Error, LocalizedError, Sendable {
    let kind: TrinkErrorKind
    let message: String
    let statusCode: Int?

    /// `true` nur, wenn die Anfrage den Server nachweislich nie erreicht hat.
    /// Nur solche Schreibaktionen dürfen in die Warteschlange — sonst droht bei
    /// einem Timeout mitten in der Übertragung eine Doppel-Anlage (Spec 3.1).
    let neverSent: Bool

    init(_ kind: TrinkErrorKind, _ message: String, statusCode: Int? = nil, neverSent: Bool = false) {
        self.kind = kind
        self.message = message
        self.statusCode = statusCode
        self.neverSent = neverSent
    }

    /// Dauerhafte Fehler nimmt die Warteschlange nicht wieder auf.
    var isPermanent: Bool {
        kind == .validation || kind == .unsupported || kind == .configuration
    }

    var errorDescription: String? { message }
}

/// Für die UI: jede Fehlermeldung als Text, `TrinkError` unverändert.
func errorText(_ error: Error) -> String {
    if let e = error as? TrinkError { return e.message }
    return "Unerwarteter Fehler: \(error.localizedDescription)"
}
