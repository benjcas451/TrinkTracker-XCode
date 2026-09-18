import Foundation
import Testing
@testable import TrinkTracker

@MainActor
struct OfflineServiceTests {
    private func make(_ fake: FakeService, key: String = "trink:apiKey|https://t.example/api.php") -> (OfflineService, UserDefaults) {
        let defaults = freshDefaults()
        return (OfflineService(inner: fake, queueKey: key, defaults: defaults), defaults)
    }

    @Test func nachweislichUngesendeteSchreibaktionWandertInDieWarteschlange() async throws {
        let fake = FakeService()
        let (service, _) = make(fake)
        fake.reachable = false
        fake.neverSent = true

        let entry = try await service.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 250, createTime: nil)
        #expect(entry.isPending)
        #expect(service.pendingCount == 1)
        #expect(service.isOffline)
        #expect(fake.createEntryCalls == 0)
    }

    @Test func beiUnklaremAusgangWirdNichtEingereiht() async {
        let fake = FakeService()
        let (service, _) = make(fake)
        fake.reachable = false
        fake.neverSent = false

        await #expect(throws: TrinkError.self) {
            _ = try await service.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 250, createTime: nil)
        }
        #expect(service.pendingCount == 0)
    }

    @Test func warteschlangeLaeuftNachUndLegtJedenEintragGenauEinmalAn() async throws {
        let fake = FakeService()
        let (service, _) = make(fake)
        fake.reachable = false
        _ = try await service.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 250, createTime: nil)
        _ = try await service.createEntry(userId: 1, getraenk: "Tee", mengeMl: 200, createTime: nil)
        #expect(service.pendingCount == 2)

        fake.reachable = true
        await service.flush()
        await service.flush()
        #expect(service.pendingCount == 0)
        #expect(fake.createEntryCalls == 2)
        #expect(fake.entries.map(\.getraenk) == ["Wasser", "Tee"])
        #expect(!service.isOffline)
    }

    @Test func lesenZeigtBeiNetzfehlerDenLetztenErfolgreichenStand() async throws {
        let fake = FakeService()
        let (service, _) = make(fake)
        _ = try await fake.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 300, createTime: nil)
        let online = try await service.getEntries(userId: 1, limit: 50)
        #expect(online.count == 1)

        fake.reachable = false
        let cached = try await service.getEntries(userId: 1, limit: 50)
        #expect(cached.map(\.mengeMl) == [300])
        #expect(service.isOffline)
    }

    @Test func ohneCacheMeldetLesenDenNetzfehler() async {
        let fake = FakeService()
        let (service, _) = make(fake)
        fake.reachable = false
        await #expect(throws: TrinkError.self) { _ = try await service.getUsers() }
    }

    @Test func ausstehendeEintraegeZaehlenSofortInDieTagessumme() async throws {
        let fake = FakeService()
        let (service, _) = make(fake)
        _ = try await service.getToday(userId: 1) // Cache füllen
        _ = try await service.getEntries(userId: 1, limit: 50)
        fake.reachable = false
        _ = try await service.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 500, createTime: nil)

        let today = try await service.getToday(userId: 1)
        #expect(today.ml == 500)
        #expect(today.anzahl == 1)
        #expect(today.fortschrittPct == 25)

        let entries = try await service.getEntries(userId: 1, limit: 50)
        #expect(entries.count == 1)
        #expect(entries[0].isPending)
    }

    @Test func ausstehenderEintragLaesstSichOhneServerEntfernen() async throws {
        let fake = FakeService()
        let (service, _) = make(fake)
        fake.reachable = false
        let entry = try await service.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 500, createTime: nil)
        #expect(service.pendingCount == 1)

        try await service.deleteEntry(id: entry.id)
        #expect(service.pendingCount == 0)
    }

    @Test func dauerhaftAbgelehnteAktionenVerlassenDieWarteschlange() async throws {
        let fake = FakeService()
        let (service, _) = make(fake)
        fake.reachable = false
        _ = try await service.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 500, createTime: nil)

        fake.reachable = true
        fake.rejectWrites = true
        await service.flush()
        #expect(service.pendingCount == 0)
        #expect(service.lastQueueError == "Server lehnt die Aktion ab")
    }

    @Test func getrennteQueuesJeKennung() async throws {
        let fake = FakeService()
        let defaults = freshDefaults()
        let a = OfflineService(inner: fake, queueKey: "trink:apiKey|https://a.example", defaults: defaults)
        fake.reachable = false
        _ = try await a.createEntry(userId: 1, getraenk: "Wasser", mengeMl: 500, createTime: nil)
        #expect(a.pendingCount == 1)

        let b = OfflineService(inner: fake, queueKey: "trink:apiKey|https://b.example", defaults: defaults)
        #expect(b.pendingCount == 0)

        // Rückwechsel nimmt die alte Queue wieder auf.
        let aAgain = OfflineService(inner: fake, queueKey: "trink:apiKey|https://a.example", defaults: defaults)
        #expect(aAgain.pendingCount == 1)
    }

    @Test func queueUeberlebtNeustartUndBleibtLesbar() async throws {
        let fake = FakeService()
        let defaults = freshDefaults()
        let first = OfflineService(inner: fake, queueKey: "trink:apiKey|https://a.example", defaults: defaults)
        fake.reachable = false
        _ = try await first.setTagesziel(userId: 1, ml: 1800)

        let second = OfflineService(inner: fake, queueKey: "trink:apiKey|https://a.example", defaults: defaults)
        #expect(second.pendingCount == 1)
        fake.reachable = true
        await second.flush()
        #expect(fake.tageszielMl == 1800)
    }
}
