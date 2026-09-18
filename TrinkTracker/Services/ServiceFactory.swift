import Foundation

/// Baut den Dienst zum eingestellten Modus (Spec 3.1). Der Aufrufer legt fest,
/// ob der Offline-Wrapper darüber liegt — eine künftige Watch-Brücke nutzt ihn
/// bewusst nicht, sie führt eine eigene Outbox.
///
/// `offlineFaehig: false` liefert die nackte Server-Quelle, etwa für
/// „Verbindung testen".
@MainActor
func createConfiguredEntryService(_ settings: AppSettings, offlineFaehig: Bool = true) -> TrinkEntryService {
    let mode = settings.mode
    if mode == .demo {
        return LocalService()
    }

    let key = settings.apiKey(for: mode).trimmingCharacters(in: .whitespacesAndNewlines)
    let api = APIService(
        baseUrl: settings.baseUrl(for: mode),
        // Im mTLS- und Cloudflare-Modus ist der Key optional: leer => kein Header.
        apiKey: key.isEmpty ? nil : key,
        certificateStore: mode == .api ? ClientCertificateStore(folderPath: settings.certFolder) : nil,
        cfAccessClientId: mode == .cloudflare ? settings.cfAccessClientId : nil,
        cfAccessClientSecret: mode == .cloudflare ? settings.cfAccessClientSecret : nil,
        userManagement: settings.serverUserManagement
    )

    if !offlineFaehig { return api }
    return OfflineService(inner: api, queueKey: settings.queueKey)
}
