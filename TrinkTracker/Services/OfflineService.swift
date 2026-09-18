import Foundation
import Observation

/// Offline-Wrapper über eine Server-Quelle (Spec 3.1).
///
/// * **Lesen:** bei Netzfehler den letzten erfolgreichen Stand zeigen.
/// * **Schreiben:** nur Aktionen, die den Server nachweislich nie erreicht
///   haben (`neverSent`), landen in der Warteschlange. Alles andere — etwa ein
///   Timeout mitten in der Übertragung — meldet den Fehler, sonst droht eine
///   Doppel-Anlage.
@Observable
@MainActor
final class OfflineService: TrinkEntryService {
    static let cachePrefix = "trinktracker.cache."

    @ObservationIgnored private let inner: TrinkEntryService
    let queueKey: String
    nonisolated let supportsUserManagement: Bool
    @ObservationIgnored private let queue: OfflineQueue
    @ObservationIgnored private let defaults: UserDefaults

    /// Letzter Lese- oder Schreibversuch scheiterte am Netz.
    private(set) var isOffline = false

    /// Anzahl ausstehender Schreibaktionen — Grundlage für das Offline-Banner.
    private(set) var pendingCount = 0

    /// Grund, warum eine Aktion aus der Warteschlange endgültig verworfen wurde.
    private(set) var lastQueueError: String?

    @ObservationIgnored private var flushing = false

    init(inner: TrinkEntryService, queueKey: String, defaults: UserDefaults = .standard) {
        self.inner = inner
        self.queueKey = queueKey
        self.queue = OfflineQueue(queueKey: queueKey, defaults: defaults)
        self.defaults = defaults
        self.supportsUserManagement = inner.supportsUserManagement
        self.pendingCount = queue.count
    }

    func refreshPendingCount() {
        let count = queue.count
        if count != pendingCount { pendingCount = count }
    }

    private func setOffline(_ value: Bool) {
        if isOffline != value { isOffline = value }
    }

    // MARK: Lese-Cache

    private func cacheKey(_ name: String) -> String { "\(Self.cachePrefix)\(queueKey)|\(name)" }

    private func writeCache(_ name: String, _ value: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            defaults.set(String(decoding: data, as: UTF8.self), forKey: cacheKey(name))
        }
    }

    private func readCache(_ name: String) -> Any? {
        // Auch den Cache der Flutter-Version lesen, falls vorhanden.
        let raw = defaults.string(forKey: cacheKey(name)) ?? defaults.string(forKey: "flutter." + cacheKey(name))
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func read<T>(
        _ name: String,
        fetch: () async throws -> T,
        encode: (T) -> Any,
        decode: (Any) -> T?
    ) async throws -> T {
        do {
            let value = try await fetch()
            setOffline(false)
            writeCache(name, encode(value))
            return value
        } catch let error as TrinkError where error.kind == .network {
            setOffline(true)
            guard let cached = readCache(name), let value = decode(cached) else { throw error }
            return value
        }
    }

    private func objects(_ json: Any) -> [[String: Any]] {
        (json as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    // MARK: Lesen

    func getUsers() async throws -> [TrinkUser] {
        try await read(
            "users",
            fetch: { try await inner.getUsers() },
            encode: { $0.map(\.json) },
            decode: { [self] in objects($0).map(TrinkUser.init(json:)) }
        )
    }

    func getEntries(userId: Int, limit: Int) async throws -> [TrinkEntry] {
        let server = try await read(
            "entries:\(userId):\(limit)",
            fetch: { try await inner.getEntries(userId: userId, limit: limit) },
            encode: { $0.map(\.json) },
            decode: { [self] in objects($0).map { TrinkEntry(json: $0, userId: userId) } }
        )
        return withPending(userId: userId, server: server)
    }

    /// Blendet die Warteschlange in die Liste ein: ausstehende Einträge werden
    /// gezeigt (negative ID), ausstehende Löschungen verschwinden sofort.
    private func withPending(userId: Int, server: [TrinkEntry]) -> [TrinkEntry] {
        let ops = queue.load()
        if ops.isEmpty { return server }

        let deleted = Set(ops.filter { $0.type == .deleteEntry }.map { $0.int("id") })
        var merged: [TrinkEntry] = ops
            .filter { $0.type == .entry && $0.userId == userId }
            .map { op in
                TrinkEntry(
                    id: op.localId,
                    userId: userId,
                    getraenk: op.string("getraenk"),
                    mengeMl: op.int("menge_ml"),
                    createdAt: parseServerTime(op.string("create_time"))
                )
            }
        merged.append(contentsOf: server.filter { !deleted.contains($0.id) })
        merged.sort { $0.createdAt > $1.createdAt }
        return merged
    }

    func getToday(userId: Int) async throws -> TodayStats {
        let base = try await read(
            "today:\(userId)",
            fetch: { try await inner.getToday(userId: userId) },
            encode: { $0.json },
            decode: { ($0 as? [String: Any]).map(TodayStats.init(json:)) }
        )
        return todayWithPending(userId: userId, base: base)
    }

    private func todayWithPending(userId: Int, base: TodayStats) -> TodayStats {
        let ops = queue.load()
        if ops.isEmpty { return base }

        var ml = base.ml
        var anzahl = base.anzahl
        var ziel = base.tageszielMl
        for op in ops where op.userId == userId {
            switch op.type {
            case .entry:
                ml += op.int("menge_ml")
                anzahl += 1
            case .ziel:
                ziel = op.int("tagesziel_ml")
            case .favorite, .deleteEntry, .undoLast:
                break
            }
        }
        return TodayStats(ml: ml, anzahl: anzahl, tageszielMl: ziel)
    }

    func getStats(userId: Int) async throws -> StatsBundle {
        try await read(
            "stats:\(userId)",
            fetch: { try await inner.getStats(userId: userId) },
            encode: { $0.json },
            decode: { ($0 as? [String: Any]).map(StatsBundle.init(json:)) }
        )
    }

    func getFavorites(userId: Int) async throws -> [TrinkFavorite] {
        try await read(
            "favorites:\(userId)",
            fetch: { try await inner.getFavorites(userId: userId) },
            encode: { $0.map(\.json) },
            decode: { [self] in objects($0).map { TrinkFavorite(json: $0, userId: userId) } }
        )
    }

    // MARK: Schreiben

    /// Führt eine Schreibaktion aus und reiht sie **nur** ein, wenn sie den
    /// Server nachweislich nie erreicht hat.
    private func write<T>(
        send: () async throws -> T,
        type: QueuedOpType,
        payload: [String: JSONScalar],
        queued: (QueuedOp) -> T
    ) async throws -> T {
        do {
            let result = try await send()
            setOffline(false)
            Task { await flush() }
            return result
        } catch let error as TrinkError where error.kind == .network {
            setOffline(true)
            // Ausgang unklar — nicht einreihen, sonst Doppel-Anlage (Spec 3.1/9.4).
            guard error.neverSent else { throw error }
            let op = queue.add(type, payload)
            refreshPendingCount()
            return queued(op)
        }
    }

    func createEntry(userId: Int, getraenk: String, mengeMl: Int, createTime: Date?) async throws -> TrinkEntry {
        let when = createTime ?? Date()
        return try await write(
            send: { try await inner.createEntry(userId: userId, getraenk: getraenk, mengeMl: mengeMl, createTime: when) },
            type: .entry,
            payload: [
                "user_id": .int(userId),
                "getraenk": .string(getraenk),
                "menge_ml": .int(mengeMl),
                "create_time": .string(iso8601String(when)),
            ],
            queued: { op in
                TrinkEntry(id: op.localId, userId: userId, getraenk: getraenk, mengeMl: mengeMl, createdAt: when)
            }
        )
    }

    func createFavorite(userId: Int, getraenk: String, mengeMl: Int) async throws -> TrinkFavorite {
        try await write(
            send: { try await inner.createFavorite(userId: userId, getraenk: getraenk, mengeMl: mengeMl) },
            type: .favorite,
            payload: ["user_id": .int(userId), "getraenk": .string(getraenk), "menge_ml": .int(mengeMl)],
            queued: { op in TrinkFavorite(id: op.localId, userId: userId, getraenk: getraenk, mengeMl: mengeMl) }
        )
    }

    func setTagesziel(userId: Int, ml: Int) async throws {
        try await write(
            send: { try await inner.setTagesziel(userId: userId, ml: ml) },
            type: .ziel,
            payload: ["user_id": .int(userId), "tagesziel_ml": .int(ml)],
            queued: { _ in () }
        )
    }

    func deleteEntry(id: Int) async throws {
        if id < 0 {
            // Noch nicht gesendet: einfach aus der Warteschlange nehmen.
            _ = queue.removeEntry(localId: id)
            refreshPendingCount()
            return
        }
        try await write(
            send: { try await inner.deleteEntry(id: id) },
            type: .deleteEntry,
            payload: ["id": .int(id)],
            queued: { _ in () }
        )
    }

    func undoLast(userId: Int) async throws {
        try await write(
            send: { try await inner.undoLast(userId: userId) },
            type: .undoLast,
            payload: ["user_id": .int(userId)],
            queued: { _ in () }
        )
    }

    // Nutzer-/Favoritenverwaltung wird nicht eingereiht: sie erzeugt IDs, auf die
    // spätere Aktionen verweisen. Offline meldet sie schlicht den Netzfehler.
    func createUser(name: String) async throws -> TrinkUser { try await inner.createUser(name: name) }
    func renameUser(userId: Int, name: String) async throws { try await inner.renameUser(userId: userId, name: name) }
    func deleteUser(userId: Int) async throws { try await inner.deleteUser(userId: userId) }
    func deleteFavorite(id: Int) async throws { try await inner.deleteFavorite(id: id) }

    // MARK: Flush

    /// Arbeitet die Warteschlange der Reihe nach ab. Bricht beim ersten
    /// Netzfehler ab (Reihenfolge bleibt erhalten); dauerhaft abgelehnte
    /// Aktionen werden verworfen und in `lastQueueError` gemeldet.
    func flush() async {
        if flushing { return }
        flushing = true
        defer {
            flushing = false
            refreshPendingCount()
        }
        for op in queue.load() {
            do {
                try await execute(op)
                queue.remove(op)
                // Der Server hat geantwortet — der Offline-Zustand ist vorbei.
                setOffline(false)
            } catch let error as TrinkError {
                if error.kind == .network {
                    setOffline(true)
                    return
                }
                if error.isPermanent {
                    lastQueueError = error.message
                    queue.remove(op)
                    continue
                }
                // Auth- oder Serverfehler: stehen lassen, später erneut versuchen.
                return
            } catch {
                return
            }
        }
    }

    private func execute(_ op: QueuedOp) async throws {
        switch op.type {
        case .entry:
            _ = try await inner.createEntry(
                userId: op.userId,
                getraenk: op.string("getraenk"),
                mengeMl: op.int("menge_ml"),
                createTime: parseServerTime(op.string("create_time"))
            )
        case .favorite:
            _ = try await inner.createFavorite(userId: op.userId, getraenk: op.string("getraenk"), mengeMl: op.int("menge_ml"))
        case .ziel:
            try await inner.setTagesziel(userId: op.userId, ml: op.int("tagesziel_ml"))
        case .deleteEntry:
            try await inner.deleteEntry(id: op.int("id"))
        case .undoLast:
            try await inner.undoLast(userId: op.userId)
        }
    }

    func testConnection() async throws -> Int { try await inner.testConnection() }

    func dispose() async { await inner.dispose() }
}
