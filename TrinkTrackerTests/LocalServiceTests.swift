import Foundation
import Testing
@testable import TrinkTracker

struct LocalServiceTests {
    private func makeService() -> LocalService {
        let path = NSTemporaryDirectory() + "trinktracker-test-\(UUID().uuidString).db"
        return LocalService(path: path)
    }

    @Test func erststartIstLeerUndNutzerLassenSichAnlegen() async throws {
        let service = makeService()
        #expect(try await service.getUsers().isEmpty)
        let user = try await service.createUser(name: " Mia ")
        #expect(user.name == "Mia")
        #expect(try await service.getUsers().count == 1)
        await #expect(throws: TrinkError.self) { _ = try await service.createUser(name: "Mia") }
    }

    @Test func eintraegeZaehlenInHeuteUndStats() async throws {
        let service = makeService()
        let user = try await service.createUser(name: "Mia")
        try await service.setTagesziel(userId: user.id, ml: 1000)
        _ = try await service.createEntry(userId: user.id, getraenk: "Wasser", mengeMl: 250, createTime: nil)
        _ = try await service.createEntry(userId: user.id, getraenk: "Tee", mengeMl: 300, createTime: nil)

        let today = try await service.getToday(userId: user.id)
        #expect(today.ml == 550)
        #expect(today.anzahl == 2)
        #expect(today.fortschrittPct == 55)
        #expect(!today.zielErreicht)

        let stats = try await service.getStats(userId: user.id)
        #expect(stats.week.ml == 550)

        try await service.undoLast(userId: user.id)
        #expect(try await service.getToday(userId: user.id).ml == 250)
    }

    @Test func favoritenSindEindeutigJeNutzer() async throws {
        let service = makeService()
        let user = try await service.createUser(name: "Mia")
        _ = try await service.createFavorite(userId: user.id, getraenk: "Wasser", mengeMl: 250)
        await #expect(throws: TrinkError.self) {
            _ = try await service.createFavorite(userId: user.id, getraenk: "Wasser", mengeMl: 250)
        }
    }

    @Test func exportUndImportSindRoundtripfaehig() async throws {
        let source = makeService()
        let user = try await source.createUser(name: "Mia")
        try await source.setTagesziel(userId: user.id, ml: 1500)
        _ = try await source.createEntry(userId: user.id, getraenk: "Wasser", mengeMl: 250, createTime: nil)
        _ = try await source.createFavorite(userId: user.id, getraenk: "Tee", mengeMl: 200)
        let backup = try await source.exportAll()

        // Über JSON, wie eine echte Datei.
        let data = try JSONSerialization.data(withJSONObject: backup)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let target = makeService()
        try await target.importAll(decoded)
        let users = try await target.getUsers()
        #expect(users.map(\.name) == ["Mia"])
        #expect(users[0].tageszielMl == 1500)
        #expect(try await target.getEntries(userId: user.id, limit: 50).map(\.mengeMl) == [250])
        #expect(try await target.getFavorites(userId: user.id).map(\.getraenk) == ["Tee"])
    }

    @Test func nutzerLoeschenEntferntEintraegeMit() async throws {
        let service = makeService()
        let user = try await service.createUser(name: "Mia")
        _ = try await service.createEntry(userId: user.id, getraenk: "Wasser", mengeMl: 250, createTime: nil)
        try await service.deleteUser(userId: user.id)
        #expect(try await service.getUsers().isEmpty)
        #expect(try await service.getEntries(userId: user.id, limit: 50).isEmpty)
    }
}
