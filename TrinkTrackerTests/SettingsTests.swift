import Foundation
import Testing
@testable import TrinkTracker

@MainActor
struct SettingsTests {
    private func make(_ defaults: UserDefaults) -> AppSettings {
        AppSettings(defaults: defaults, keychain: KeychainStore(service: "trinktracker.tests.\(UUID().uuidString)"), migrateLegacy: false)
    }

    @Test func erststartLokalerModusAlleFelderLeer() {
        let settings = make(freshDefaults())
        #expect(settings.mode == .demo)
        for mode in ConnectionMode.allCases {
            #expect(settings.baseUrl(for: mode).isEmpty)
            #expect(settings.apiKey(for: mode).isEmpty)
        }
        #expect(settings.cfAccessClientId.isEmpty)
        #expect(settings.cfAccessClientSecret.isEmpty)
        #expect(settings.selectedUserId == nil)
        #expect(settings.serverUserManagement == false)
    }

    @Test func baseUrlsDerModiUeberschreibenSichNicht() {
        let settings = make(freshDefaults())
        settings.setBaseUrl(.apiKey, "https://a.example/api.php")
        settings.setBaseUrl(.api, "https://b.example/api.php")
        settings.setBaseUrl(.cloudflare, "https://c.example/api.php")
        #expect(settings.baseUrl(for: .apiKey) == "https://a.example/api.php")
        #expect(settings.baseUrl(for: .api) == "https://b.example/api.php")
        #expect(settings.baseUrl(for: .cloudflare) == "https://c.example/api.php")
        #expect(settings.baseUrl(for: .demo).isEmpty)
    }

    @Test func queueKennungFolgtModusUndUrl() {
        let settings = make(freshDefaults())
        #expect(settings.queueKey == "trink:demo|")
        settings.setMode(.apiKey)
        settings.setBaseUrl(.apiKey, "https://a.example/api.php")
        #expect(settings.queueKey == "trink:apiKey|https://a.example/api.php")
        settings.setMode(.cloudflare)
        #expect(settings.queueKey == "trink:cloudflare|")
    }

    @Test func einstellungenUeberlebenNeustart() {
        let defaults = freshDefaults()
        let first = make(defaults)
        first.setMode(.api)
        first.setBaseUrl(.api, "https://b.example/api.php")
        first.setSelectedUserId(7)
        first.setServerUserManagement(true)

        let second = make(defaults)
        #expect(second.mode == .api)
        #expect(second.baseUrl(for: .api) == "https://b.example/api.php")
        #expect(second.selectedUserId == 7)
        #expect(second.serverUserManagement == true)
    }

    @Test func revisionZaehltVerbindungsaenderungen() {
        let settings = make(freshDefaults())
        let before = settings.revision
        settings.setMode(.apiKey)
        settings.setMode(.apiKey) // unverändert → kein Zähler
        #expect(settings.revision == before + 1)
        settings.setSelectedUserId(3) // kein Verbindungswert
        #expect(settings.revision == before + 1)
    }

    @Test func standardnutzerUeberlebtNeustartUndIstAbschaltbar() {
        let defaults = freshDefaults()
        let first = make(defaults)
        #expect(first.defaultUserId == nil)
        first.setDefaultUserId(4)
        #expect(make(defaults).defaultUserId == 4)
        first.setDefaultUserId(nil)
        #expect(make(defaults).defaultUserId == nil)
    }

    @Test func validateBaseUrlAkzeptiertHttpsMitHost() {
        #expect(validateBaseUrl("https://familie.example/trink-tracker/api.php") == nil)
        #expect(validateBaseUrl("  https://familie.example/api.php  ") == nil)
    }

    @Test func validateBaseUrlLehntHttpLeerUndUnsinnAb() {
        #expect(validateBaseUrl("") != nil)
        #expect(validateBaseUrl("http://familie.example/api.php") != nil)
        #expect(validateBaseUrl("nicht eine url") != nil)
        #expect(validateBaseUrl("https://") != nil)
    }
}
