import Foundation
@testable import TrinkTracker

/// Server-Attrappe für die Offline-Tests: speichert im Speicher und kann
/// gezielt Netzfehler werfen — wahlweise „nie gesendet" oder „Ausgang unklar".
class FakeService: TrinkEntryService, @unchecked Sendable {
    let userId: Int
    var reachable = true
    var neverSent = true

    /// Serverseitige Ablehnung (z. B. Validierung) — dauerhaft, kein Netzfehler.
    var rejectWrites = false

    var entries: [TrinkEntry] = []
    var favorites: [TrinkFavorite] = []
    var tageszielMl = 2000
    private var nextId = 1
    var createEntryCalls = 0

    init(userId: Int = 1) {
        self.userId = userId
    }

    private func guardRead() throws {
        if reachable { return }
        throw TrinkError(.network, neverSent ? "kein Netz" : "Timeout", neverSent: neverSent)
    }

    private func guardWrite() throws {
        try guardRead()
        if rejectWrites { throw TrinkError(.validation, "Server lehnt die Aktion ab") }
    }

    var supportsUserManagement: Bool { true }

    func getUsers() async throws -> [TrinkUser] {
        try guardRead()
        return [TrinkUser(id: userId, name: "Testnutzer", tageszielMl: tageszielMl)]
    }

    func getEntries(userId: Int, limit: Int) async throws -> [TrinkEntry] {
        try guardRead()
        return Array(entries.reversed().prefix(limit))
    }

    func getToday(userId: Int) async throws -> TodayStats {
        try guardRead()
        let ml = entries.reduce(0) { $0 + $1.mengeMl }
        return TodayStats(ml: ml, anzahl: entries.count, tageszielMl: tageszielMl)
    }

    func getStats(userId: Int) async throws -> StatsBundle {
        try guardRead()
        let ml = entries.reduce(0) { $0 + $1.mengeMl }
        let p = PeriodStats(ml: ml, anzahl: entries.count)
        return StatsBundle(today: p, week: p, month: p)
    }

    func getFavorites(userId: Int) async throws -> [TrinkFavorite] {
        try guardRead()
        return favorites
    }

    func createEntry(userId: Int, getraenk: String, mengeMl: Int, createTime: Date?) async throws -> TrinkEntry {
        try guardWrite()
        createEntryCalls += 1
        let entry = TrinkEntry(id: nextId, userId: userId, getraenk: getraenk, mengeMl: mengeMl, createdAt: createTime ?? Date())
        nextId += 1
        entries.append(entry)
        return entry
    }

    func createFavorite(userId: Int, getraenk: String, mengeMl: Int) async throws -> TrinkFavorite {
        try guardWrite()
        let favorite = TrinkFavorite(id: nextId, userId: userId, getraenk: getraenk, mengeMl: mengeMl)
        nextId += 1
        favorites.append(favorite)
        return favorite
    }

    func setTagesziel(userId: Int, ml: Int) async throws {
        try guardWrite()
        tageszielMl = ml
    }

    func deleteEntry(id: Int) async throws {
        try guardWrite()
        entries.removeAll { $0.id == id }
    }

    func undoLast(userId: Int) async throws {
        try guardWrite()
        _ = entries.popLast()
    }

    func createUser(name: String) async throws -> TrinkUser {
        try guardWrite()
        return TrinkUser(id: 99, name: name, tageszielMl: 0)
    }

    func renameUser(userId: Int, name: String) async throws { try guardWrite() }
    func deleteUser(userId: Int) async throws { try guardWrite() }
    func deleteFavorite(id: Int) async throws { try guardWrite() }

    func testConnection() async throws -> Int { try await getUsers().count }

    func dispose() async {}
}

/// Frische, isolierte UserDefaults je Test.
func freshDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let suite = "trinktracker.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
