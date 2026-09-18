import Foundation
import Observation

/// Bindeglied zwischen Einstellungen, Dienst und UI.
///
/// Der Dienst wird aus den Einstellungen gebaut und bei jeder Änderung von
/// Modus, Basis-URL oder Zugangsdaten neu erzeugt — ohne Neustart (Spec 3.2).
@Observable
@MainActor
final class AppStore {
    let settings: AppSettings

    /// Nur für Tests: umgeht die Factory und nutzt den übergebenen Dienst.
    @ObservationIgnored private let override: TrinkEntryService?

    @ObservationIgnored private var currentService: TrinkEntryService?
    @ObservationIgnored private var signature = ""

    private(set) var users: [TrinkUser] = []
    private(set) var todayByUser: [Int: TodayStats] = [:]
    private(set) var entries: [TrinkEntry] = []
    private(set) var favorites: [TrinkFavorite] = []
    private(set) var stats: StatsBundle = .empty

    /// Bis zu 500 Einträge für die 7-Tage-/30-Tage-Auswertung.
    private(set) var historyEntries: [TrinkEntry] = []

    private(set) var loading = false
    private(set) var errorMessage: String?

    /// Der Standardnutzer greift einmal je App-Start — danach darf man frei
    /// zwischen Familienmitgliedern wechseln, ohne zurückgesetzt zu werden.
    @ObservationIgnored private var defaultUserApplied = false

    /// Der aktuell wirksame Offline-Wrapper (nur Server-Modi) — beobachtbar.
    private(set) var offline: OfflineService?

    init(settings: AppSettings, serviceOverride: TrinkEntryService? = nil) {
        self.settings = settings
        self.override = serviceOverride
    }

    var selectedUserId: Int? { settings.selectedUserId }

    var selectedUser: TrinkUser? {
        guard let id = selectedUserId else { return nil }
        return users.first { $0.id == id }
    }

    var selectedToday: TodayStats {
        selectedUserId.flatMap { todayByUser[$0] } ?? .empty
    }

    /// Aktueller Dienst; wird bei Bedarf neu gebaut.
    var service: TrinkEntryService {
        if let override { return override }

        let current = currentSignature()
        if let existing = currentService, current == signature { return existing }

        if let existing = currentService {
            // Alten Dienst abräumen — die Warteschlange liegt persistent daneben und
            // überlebt den Wechsel (Spec 3.1).
            Task { await existing.dispose() }
        }
        let created = createConfiguredEntryService(settings)
        offline = created as? OfflineService
        if let offline {
            offline.refreshPendingCount()
            Task { await offline.flush() }
        }
        signature = current
        currentService = created
        return created
    }

    private func currentSignature() -> String {
        let mode = settings.mode
        return [
            mode.key,
            settings.baseUrl(for: mode),
            settings.apiKey(for: mode),
            mode == .cloudflare ? settings.cfAccessClientId : "",
            mode == .cloudflare ? settings.cfAccessClientSecret : "",
            mode == .api ? settings.certFolder : "",
            String(settings.serverUserManagement),
        ].joined(separator: "|")
    }

    var isOffline: Bool { offline?.isOffline ?? false }
    var pendingCount: Int { offline?.pendingCount ?? 0 }
    var supportsUserManagement: Bool { service.supportsUserManagement }

    /// Von der UI aufgerufen, wenn sich Verbindungseinstellungen geändert haben.
    func settingsChanged() {
        if currentSignature() != signature {
            Task { await refresh() }
        }
    }

    /// Lädt alles neu: Nutzerliste, Familienübersicht und die Daten des
    /// ausgewählten Nutzers.
    func refresh() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        let s = service
        do {
            let loadedUsers = try await s.getUsers()
            users = loadedUsers

            var selected = settings.selectedUserId
            if !defaultUserApplied, let preferred = settings.defaultUserId,
               loadedUsers.contains(where: { $0.id == preferred }) {
                selected = preferred
            }
            defaultUserApplied = true
            if let current = selected, !loadedUsers.contains(where: { $0.id == current }) {
                selected = nil
            }
            if selected == nil { selected = loadedUsers.first?.id }
            if selected != settings.selectedUserId {
                settings.setSelectedUserId(selected)
            }

            var today: [Int: TodayStats] = [:]
            for user in loadedUsers {
                today[user.id] = try await s.getToday(userId: user.id)
            }
            todayByUser = today

            if let selected {
                entries = try await s.getEntries(userId: selected)
                favorites = try await s.getFavorites(userId: selected)
                stats = try await s.getStats(userId: selected)
                historyEntries = try await s.getEntries(userId: selected, limit: 500)
            } else {
                entries = []
                favorites = []
                historyEntries = []
                stats = .empty
            }
        } catch {
            errorMessage = errorText(error)
        }
    }

    func selectUser(_ userId: Int) async {
        settings.setSelectedUserId(userId)
        await refresh()
    }

    var defaultUserId: Int? { settings.defaultUserId }

    func isDefaultUser(_ user: TrinkUser) -> Bool { user.id == settings.defaultUserId }

    /// Setzt oder löscht den Standardnutzer dieses Geräts und wählt ihn sofort aus.
    func setDefaultUser(_ user: TrinkUser?) async {
        settings.setDefaultUserId(user?.id)
        if let user {
            await selectUser(user.id)
        }
    }

    /// Führt eine Schreibaktion aus und lädt danach neu. Liefert `nil` bei
    /// Erfolg, sonst die Fehlermeldung für die UI.
    func run(_ action: (TrinkEntryService) async throws -> Void) async -> String? {
        do {
            try await action(service)
            await refresh()
            return nil
        } catch let error as TrinkError {
            errorMessage = error.message
            await refresh()
            return error.message
        } catch {
            let message = errorText(error)
            errorMessage = message
            return message
        }
    }

    func addEntry(_ getraenk: String, _ mengeMl: Int, createTime: Date? = nil) async -> String? {
        guard let userId = selectedUserId else { return "Bitte zuerst einen Nutzer anlegen." }
        return await run { _ = try await $0.createEntry(userId: userId, getraenk: getraenk, mengeMl: mengeMl, createTime: createTime) }
    }

    func addFavorite(_ getraenk: String, _ mengeMl: Int) async -> String? {
        guard let userId = selectedUserId else { return "Bitte zuerst einen Nutzer anlegen." }
        return await run { _ = try await $0.createFavorite(userId: userId, getraenk: getraenk, mengeMl: mengeMl) }
    }

    func deleteEntry(_ id: Int) async -> String? {
        await run { try await $0.deleteEntry(id: id) }
    }

    func undoLast() async -> String? {
        guard let userId = selectedUserId else { return "Kein Nutzer ausgewählt." }
        return await run { try await $0.undoLast(userId: userId) }
    }

    func setTagesziel(_ userId: Int, _ ml: Int) async -> String? {
        await run { try await $0.setTagesziel(userId: userId, ml: ml) }
    }

    func createUser(_ name: String) async -> String? {
        await run { _ = try await $0.createUser(name: name) }
    }

    func renameUser(_ userId: Int, _ name: String) async -> String? {
        await run { try await $0.renameUser(userId: userId, name: name) }
    }

    func deleteUser(_ userId: Int) async -> String? {
        await run { try await $0.deleteUser(userId: userId) }
    }

    func deleteFavorite(_ id: Int) async -> String? {
        await run { try await $0.deleteFavorite(id: id) }
    }

    /// Schickt die Warteschlange erneut los.
    func flushQueue() async {
        _ = service
        guard let offline else { return }
        await offline.flush()
        await refresh()
    }

    /// Der lokale Modus für Backup/Export — `nil` in Server-Modi.
    var localService: LocalService? { service as? LocalService }
}
