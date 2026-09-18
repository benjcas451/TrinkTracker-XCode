import Foundation
import Testing
@testable import TrinkTracker

/// Server-Attrappe mit mehreren Nutzern für die Auswahl-Logik des Stores.
private final class FamilyService: FakeService, @unchecked Sendable {
    override func getUsers() async throws -> [TrinkUser] {
        [
            TrinkUser(id: 1, name: "Ben", tageszielMl: 1500),
            TrinkUser(id: 2, name: "Mia", tageszielMl: 2000),
        ]
    }
}

@MainActor
struct AppStoreTests {
    private func make() -> (AppStore, AppSettings) {
        let settings = AppSettings(
            defaults: freshDefaults(),
            keychain: KeychainStore(service: "trinktracker.tests.\(UUID().uuidString)"),
            migrateLegacy: false
        )
        return (AppStore(settings: settings, serviceOverride: FamilyService()), settings)
    }

    @Test func ohneStandardnutzerStartetDerErsteNutzer() async {
        let (store, _) = make()
        await store.refresh()
        #expect(store.selectedUserId == 1)
    }

    @Test func standardnutzerGewinntBeimStartGegenLetzteAuswahl() async {
        let (store, settings) = make()
        settings.setSelectedUserId(1)
        settings.setDefaultUserId(2)
        await store.refresh()
        #expect(store.selectedUserId == 2)

        // Innerhalb der Sitzung darf man wechseln, ohne zurückgesetzt zu werden.
        await store.selectUser(1)
        await store.refresh()
        #expect(store.selectedUserId == 1)
    }

    @Test func unbekannterStandardnutzerWirdIgnoriert() async {
        let (store, settings) = make()
        settings.setDefaultUserId(99)
        await store.refresh()
        #expect(store.selectedUserId == 1)
    }
}
