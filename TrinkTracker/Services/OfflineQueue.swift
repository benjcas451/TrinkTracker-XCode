import Foundation

/// Art der ausstehenden Schreibaktion.
enum QueuedOpType: String, Codable, Sendable {
    case entry, favorite, ziel, deleteEntry, undoLast
}

/// Eine Schreibaktion, die den Server nachweislich nie erreicht hat (Spec 3.1).
struct QueuedOp: Sendable {
    let localId: Int
    let type: QueuedOpType
    let payload: [String: JSONScalar]
    let queuedAt: Date

    var userId: Int { payload["user_id"]?.intValue ?? 0 }

    func int(_ key: String) -> Int { payload[key]?.intValue ?? 0 }
    func string(_ key: String) -> String { payload[key]?.stringValue ?? "" }

    var json: [String: Any] {
        [
            "local_id": localId,
            "type": type.rawValue,
            "payload": payload.mapValues(\.anyValue),
            "queued_at": iso8601String(queuedAt),
        ]
    }

    init(localId: Int, type: QueuedOpType, payload: [String: JSONScalar], queuedAt: Date) {
        self.localId = localId
        self.type = type
        self.payload = payload
        self.queuedAt = queuedAt
    }

    init?(json: [String: Any]) {
        guard let type = QueuedOpType(rawValue: asString(json["type"])) else { return nil }
        let raw = json["payload"] as? [String: Any] ?? [:]
        self.init(
            localId: asInt(json["local_id"]),
            type: type,
            payload: raw.compactMapValues(JSONScalar.init(any:)),
            queuedAt: parseServerTime(json["queued_at"])
        )
    }
}

/// Skalare Payload-Werte — `Sendable`, damit Queue-Einträge frei zwischen
/// Actor und Hauptthread wandern.
enum JSONScalar: Sendable, Hashable {
    case int(Int)
    case string(String)
    case bool(Bool)

    init?(any: Any) {
        switch any {
        case let v as Bool: self = .bool(v)
        case let v as Int: self = .int(v)
        case let v as Double: self = .int(Int(v.rounded()))
        case let v as NSNumber: self = .int(v.intValue)
        case let v as String: self = .string(v)
        default: return nil
        }
    }

    var intValue: Int {
        switch self {
        case .int(let v): return v
        case .string(let v): return Int(v.trimmingCharacters(in: .whitespaces)) ?? 0
        case .bool(let v): return v ? 1 : 0
        }
    }

    var stringValue: String {
        switch self {
        case .int(let v): return String(v)
        case .string(let v): return v
        case .bool(let v): return v ? "true" : "false"
        }
    }

    var anyValue: Any {
        switch self {
        case .int(let v): return v
        case .string(let v): return v
        case .bool(let v): return v
        }
    }
}

/// Persistente Warteschlange, getrennt je Modus **und** Basis-URL:
/// Kennung `trink:<mode>|<baseUrl>` (Spec 3.1). Ein URL-Wechsel legt damit eine
/// neue Queue an; die alte bleibt unberührt und läuft nach einem Rückwechsel
/// weiter.
final class OfflineQueue: @unchecked Sendable {
    static let storagePrefix = "trinktracker.queue."

    let queueKey: String
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var ops: [QueuedOp]?

    init(queueKey: String, defaults: UserDefaults = .standard) {
        self.queueKey = queueKey
        self.defaults = defaults
    }

    private var storageKey: String { Self.storagePrefix + queueKey }

    func load() -> [QueuedOp] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    private func loadLocked() -> [QueuedOp] {
        if let ops { return ops }
        // Eine noch nicht gesendete Warteschlange der Flutter-Version übernehmen.
        let raw = defaults.string(forKey: storageKey) ?? defaults.string(forKey: "flutter." + storageKey)
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            ops = []
            return []
        }
        let loaded = decoded.compactMap { ($0 as? [String: Any]).flatMap(QueuedOp.init(json:)) }
        ops = loaded
        return loaded
    }

    private func persistLocked(_ newOps: [QueuedOp]) {
        ops = newOps
        if newOps.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONSerialization.data(withJSONObject: newOps.map(\.json)) {
            defaults.set(String(decoding: data, as: UTF8.self), forKey: storageKey)
        }
        defaults.removeObject(forKey: "flutter." + storageKey)
    }

    /// Lokale IDs sind negativ und über die Queue hinweg eindeutig (Spec 4).
    private func nextLocalIdLocked() -> Int {
        (loadLocked().map(\.localId).min() ?? 0).clamped(max: 0) - 1
    }

    @discardableResult
    func add(_ type: QueuedOpType, _ payload: [String: JSONScalar]) -> QueuedOp {
        lock.lock()
        defer { lock.unlock() }
        let op = QueuedOp(localId: nextLocalIdLocked(), type: type, payload: payload, queuedAt: Date())
        persistLocked(loadLocked() + [op])
        return op
    }

    func remove(_ op: QueuedOp) {
        lock.lock()
        defer { lock.unlock() }
        persistLocked(loadLocked().filter { $0.localId != op.localId })
    }

    /// Entfernt einen noch nicht gesendeten Eintrag — das ist das Undo für
    /// offline erfasste Einträge (negative ID).
    func removeEntry(localId: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let current = loadLocked()
        guard current.contains(where: { $0.type == .entry && $0.localId == localId }) else { return false }
        persistLocked(current.filter { !($0.type == .entry && $0.localId == localId) })
        return true
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        persistLocked([])
    }

    var count: Int { load().count }
}

private extension Int {
    func clamped(max upper: Int) -> Int { Swift.min(self, upper) }
}
