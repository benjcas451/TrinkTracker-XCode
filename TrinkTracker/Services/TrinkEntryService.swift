import Foundation

/// Gemeinsames Protokoll über **alle** Verbindungsmodi (Spec 3.1 / 4).
/// Implementierungen: `APIService`, `LocalService`, dazu der `OfflineService`
/// als Wrapper über eine Server-Quelle.
protocol TrinkEntryService: AnyObject {
    func getUsers() async throws -> [TrinkUser]

    /// Neueste zuerst. Der Heute-Screen zeigt daraus heute & gestern,
    /// die Statistik lädt mit größerem `limit`.
    func getEntries(userId: Int, limit: Int) async throws -> [TrinkEntry]

    func getToday(userId: Int) async throws -> TodayStats

    func getStats(userId: Int) async throws -> StatsBundle

    func getFavorites(userId: Int) async throws -> [TrinkFavorite]

    func createEntry(userId: Int, getraenk: String, mengeMl: Int, createTime: Date?) async throws -> TrinkEntry

    func createFavorite(userId: Int, getraenk: String, mengeMl: Int) async throws -> TrinkFavorite

    func setTagesziel(userId: Int, ml: Int) async throws

    func deleteEntry(id: Int) async throws

    func undoLast(userId: Int) async throws

    /// Nutzer- und Favoritenverwaltung gibt es nur, wo der Endpunkt existiert:
    /// lokal immer, serverseitig erst mit der API-Erweiterung (Spec 2.2 Option A).
    var supportsUserManagement: Bool { get }

    func createUser(name: String) async throws -> TrinkUser

    func renameUser(userId: Int, name: String) async throws

    func deleteUser(userId: Int) async throws

    func deleteFavorite(id: Int) async throws

    /// Prüft die hinterlegte Verbindung und liefert die Anzahl gefundener
    /// Nutzer („Verbindung testen", Spec 3.2).
    func testConnection() async throws -> Int

    /// Ressourcen freigeben (HTTP-Session, Datenbank).
    func dispose() async
}

extension TrinkEntryService {
    func getEntries(userId: Int) async throws -> [TrinkEntry] {
        try await getEntries(userId: userId, limit: 50)
    }

    func createEntry(userId: Int, getraenk: String, mengeMl: Int) async throws -> TrinkEntry {
        try await createEntry(userId: userId, getraenk: getraenk, mengeMl: mengeMl, createTime: nil)
    }
}
