import Foundation

/// Server-Anbindung für die Modi `apiKey`, `api` (mTLS) und `cloudflare`
/// (Spec 3.3). Die Basis-URL kommt immer aus den Einstellungen — im Code steht
/// kein Host.
final class APIService: TrinkEntryService, @unchecked Sendable {
    let baseUrl: String

    /// Im mTLS- und Cloudflare-Modus optional. Ist er leer/`nil`, wird **kein**
    /// `X-API-Key`-Header gesendet.
    let apiKey: String?

    let certificateStore: ClientCertificateStore?
    let cfAccessClientId: String?
    let cfAccessClientSecret: String?
    let timeout: TimeInterval

    /// Nur `true`, wenn der Mandant die Zusatz-Actions aus Spec 2.2 Option A hat.
    let userManagement: Bool

    private let delegate = SessionDelegate()
    private let lock = NSLock()
    private var session: URLSession?

    init(
        baseUrl: String,
        apiKey: String? = nil,
        certificateStore: ClientCertificateStore? = nil,
        cfAccessClientId: String? = nil,
        cfAccessClientSecret: String? = nil,
        timeout: TimeInterval = 20,
        userManagement: Bool = false
    ) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.certificateStore = certificateStore
        self.cfAccessClientId = cfAccessClientId
        self.cfAccessClientSecret = cfAccessClientSecret
        self.timeout = timeout
        self.userManagement = userManagement
    }

    var supportsUserManagement: Bool { userManagement }

    // MARK: Aufbau

    private func url(_ action: String, _ query: [String: String] = [:]) throws -> URL {
        let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw TrinkError(.configuration, "Basis-URL fehlt. Bitte in den Einstellungen eintragen.")
        }
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty else {
            throw TrinkError(
                .configuration,
                "Basis-URL ist ungültig. Erwartet wird \(trimmed) im Format https://…/trink-tracker/api.php"
            )
        }
        var items = (components.queryItems ?? []).filter { $0.name != "action" && query[$0.name] == nil }
        items.append(URLQueryItem(name: "action", value: action))
        for (name, value) in query.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw TrinkError(.configuration, "Basis-URL ist ungültig.")
        }
        return url
    }

    private func currentSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = false
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        let created = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        session = created
        return created
    }

    private func headers() -> [String: String] {
        var headers = ["Accept": "application/json"]
        if let key = apiKey?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            headers["X-API-Key"] = key
        }
        let cfId = cfAccessClientId?.trimmingCharacters(in: .whitespaces) ?? ""
        let cfSecret = cfAccessClientSecret?.trimmingCharacters(in: .whitespaces) ?? ""
        if !cfId.isEmpty, !cfSecret.isEmpty {
            headers["CF-Access-Client-Id"] = cfId
            headers["CF-Access-Client-Secret"] = cfSecret
        }
        return headers
    }

    // MARK: Senden

    private func send(_ method: String, _ url: URL, body: [String: Any]? = nil) async throws -> [String: Any] {
        // Zertifikat vor dem Request auflösen: Konfigurationsfehler sollen als
        // solche erscheinen — nicht als abgebrochener TLS-Handshake.
        if let store = certificateStore {
            delegate.identity = try store.identity()
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (name, value) in headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await currentSession().data(for: request)
        } catch let error as URLError {
            throw Self.map(error, host: url.host ?? "", timeout: timeout)
        } catch {
            throw TrinkError(.network, "Verbindung fehlgeschlagen: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw TrinkError(.server, "Antwort von \(url.host ?? "Server") war keine HTTP-Antwort.")
        }
        return try interpret(http, data, url)
    }

    /// Transportfehler einordnen. `neverSent` nur dort, wo die Verbindung
    /// nachweislich nie zustande kam — ein Timeout oder Abbruch während der
    /// Übertragung bleibt „Ausgang unklar" (Spec 3.1).
    private static func map(_ error: URLError, host: String, timeout: TimeInterval) -> TrinkError {
        switch error.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return TrinkError(.network, "Keine Verbindung zu \(host): \(error.localizedDescription)", neverSent: true)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return TrinkError(.network, "TLS-Handshake fehlgeschlagen: \(error.localizedDescription)", neverSent: true)
        case .timedOut:
            return TrinkError(
                .network,
                "Zeitüberschreitung nach \(Int(timeout)) s — der Server hat die Anfrage möglicherweise erhalten."
            )
        case .networkConnectionLost:
            return TrinkError(.network, "Verbindung abgebrochen: \(error.localizedDescription)")
        default:
            return TrinkError(.network, "Verbindung zu \(host) fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func interpret(_ response: HTTPURLResponse, _ data: Data, _ url: URL) throws -> [String: Any] {
        let status = response.statusCode
        let hasCfRay = response.value(forHTTPHeaderField: "cf-ray") != nil

        if (300..<400).contains(status) {
            let location = response.value(forHTTPHeaderField: "Location") ?? ""
            if location.contains("cloudflareaccess.com") {
                throw TrinkError(
                    .cloudflareLogin,
                    "Cloudflare Access hat auf die Login-Seite umgeleitet. "
                        + "Service Token in den Einstellungen prüfen – möglicherweise ist es abgelaufen.",
                    statusCode: status
                )
            }
            throw TrinkError(.server, "Unerwartete Weiterleitung (\(status)) auf \(location).", statusCode: status)
        }

        if status == 403 && hasCfRay {
            throw TrinkError(
                .cloudflarePolicy,
                "Cloudflare Access hat die Anfrage abgelehnt (403). Token ist dieser Anwendung vermutlich nicht zugewiesen.",
                statusCode: status
            )
        }

        var json: [String: Any]?
        if !data.isEmpty, let decoded = try? JSONSerialization.jsonObject(with: data) {
            json = decoded as? [String: Any]
        }

        if status == 401 || status == 403 {
            throw TrinkError(
                .auth,
                Self.message(json) ?? (status == 401
                    ? "Nicht autorisiert (401) — API-Key prüfen."
                    : "Zugriff verweigert (403) — Key, Zertifikat oder Access-Regel prüfen."),
                statusCode: status
            )
        }

        if status >= 500 {
            throw TrinkError(.server, Self.message(json) ?? "Serverfehler (\(status)).", statusCode: status)
        }

        if status >= 400 {
            throw TrinkError(.validation, Self.message(json) ?? "Anfrage abgelehnt (\(status)).", statusCode: status)
        }

        guard let json else {
            // 200 ohne JSON ist typisch für eine vorgeschaltete HTML-Seite.
            throw TrinkError(
                .server,
                "Antwort von \(url.host ?? "Server") war kein JSON. Steht vor der API eine Login- oder Fehlerseite?",
                statusCode: status
            )
        }
        return json
    }

    private static func message(_ json: [String: Any]?) -> String? {
        guard let json else { return nil }
        for key in ["error", "message", "fehler"] {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: Lesen

    func getUsers() async throws -> [TrinkUser] {
        let json = try await send("GET", url("users"))
        return jsonObjects(json, "users").map(TrinkUser.init(json:))
    }

    func getEntries(userId: Int, limit: Int) async throws -> [TrinkEntry] {
        let clamped = min(max(limit, 1), 500)
        let json = try await send("GET", url("entries", ["user_id": String(userId), "limit": String(clamped)]))
        return jsonObjects(json, "entries").map { TrinkEntry(json: $0, userId: userId) }
    }

    func getToday(userId: Int) async throws -> TodayStats {
        TodayStats(json: try await send("GET", url("heute", ["user_id": String(userId)])))
    }

    func getStats(userId: Int) async throws -> StatsBundle {
        StatsBundle(json: try await send("GET", url("stats", ["user_id": String(userId)])))
    }

    func getFavorites(userId: Int) async throws -> [TrinkFavorite] {
        let json = try await send("GET", url("favoriten", ["user_id": String(userId)]))
        return jsonObjects(json, "favoriten").map { TrinkFavorite(json: $0, userId: userId) }
    }

    // MARK: Schreiben

    func createEntry(userId: Int, getraenk: String, mengeMl: Int, createTime: Date?) async throws -> TrinkEntry {
        var body: [String: Any] = ["user_id": userId, "getraenk": getraenk, "menge_ml": mengeMl]
        if let createTime {
            body["create_time"] = BerlinTime.formatCreateTime(createTime)
        }
        let json = try await send("POST", url("eintrag"), body: body)
        return TrinkEntry(id: asInt(json["id"]), userId: userId, getraenk: getraenk, mengeMl: mengeMl, createdAt: createTime ?? Date())
    }

    func createFavorite(userId: Int, getraenk: String, mengeMl: Int) async throws -> TrinkFavorite {
        let json = try await send("POST", url("favorit"), body: ["user_id": userId, "getraenk": getraenk, "menge_ml": mengeMl])
        return TrinkFavorite(id: asInt(json["id"]), userId: userId, getraenk: getraenk, mengeMl: mengeMl)
    }

    func setTagesziel(userId: Int, ml: Int) async throws {
        _ = try await send("POST", url("ziel"), body: ["user_id": userId, "tagesziel_ml": ml])
    }

    func deleteEntry(id: Int) async throws {
        _ = try await send("POST", url("undo"), body: ["id": id])
    }

    func undoLast(userId: Int) async throws {
        _ = try await send("POST", url("undo_last"), body: ["user_id": userId])
    }

    private func requireUserManagement() throws {
        if !userManagement {
            throw TrinkError(
                .unsupported,
                "Diese Verwaltung steht in Server-Modi nur mit den Zusatz-Actions der API zur Verfügung "
                    + "(siehe Einstellungen → Erweiterte Server-Actions)."
            )
        }
    }

    func createUser(name: String) async throws -> TrinkUser {
        try requireUserManagement()
        let json = try await send("POST", url("nutzer_anlegen"), body: ["name": name])
        return TrinkUser(id: asInt(json["id"]), name: name, tageszielMl: 0)
    }

    func renameUser(userId: Int, name: String) async throws {
        try requireUserManagement()
        _ = try await send("POST", url("nutzer_umbenennen"), body: ["user_id": userId, "name": name])
    }

    func deleteUser(userId: Int) async throws {
        try requireUserManagement()
        _ = try await send("POST", url("nutzer_loeschen"), body: ["user_id": userId])
    }

    func deleteFavorite(id: Int) async throws {
        try requireUserManagement()
        _ = try await send("POST", url("favorit_loeschen"), body: ["id": id])
    }

    func testConnection() async throws -> Int {
        try await getUsers().count
    }

    private func takeSession() -> URLSession? {
        lock.lock()
        defer { lock.unlock() }
        let s = session
        session = nil
        return s
    }

    func dispose() async {
        takeSession()?.invalidateAndCancel()
    }
}

/// Redirects selbst auswerten (sonst landet die Cloudflare-Access-Loginseite
/// als HTML im JSON-Parser) und das Client-Zertifikat für mTLS liefern.
final class SessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var identity: ClientCertificateStore.Identity?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
              let identity else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(identity: identity.identity, certificates: identity.chain, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}
