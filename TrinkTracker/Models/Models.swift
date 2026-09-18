import Foundation

// MARK: - Tolerantes JSON-Parsen (Spec 3.3)

/// PHP serialisiert bool je nach Kontext als `true`/`false` oder `1`/`0`,
/// Zahlen gelegentlich als String — deshalb überall tolerant parsen.
func asInt(_ value: Any?, fallback: Int = 0) -> Int {
    switch value {
    case let v as Int: return v
    case let v as Bool: return v ? 1 : 0
    case let v as Double: return Int(v.rounded())
    case let v as NSNumber: return v.intValue
    case let v as String: return Int(v.trimmingCharacters(in: .whitespaces)) ?? fallback
    default: return fallback
    }
}

func asIntOrNull(_ value: Any?) -> Int? {
    switch value {
    case nil: return nil
    case is NSNull: return nil
    case let v as Int: return v
    case let v as Double: return Int(v.rounded())
    case let v as NSNumber: return v.intValue
    case let v as String: return Int(v.trimmingCharacters(in: .whitespaces))
    default: return nil
    }
}

func asBool(_ value: Any?) -> Bool {
    switch value {
    case let v as Bool: return v
    case let v as Int: return v != 0
    case let v as Double: return v != 0
    case let v as NSNumber: return v.doubleValue != 0
    case let v as String:
        let s = v.trimmingCharacters(in: .whitespaces).lowercased()
        return s == "1" || s == "true" || s == "yes"
    default: return false
    }
}

func asString(_ value: Any?, fallback: String = "") -> String {
    switch value {
    case nil: return fallback
    case is NSNull: return fallback
    case let v as String: return v
    default: return "\(value!)"
    }
}

/// Liste von JSON-Objekten unter `key`, alles andere wird ignoriert.
func jsonObjects(_ json: [String: Any], _ key: String) -> [[String: Any]] {
    (json[key] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
}

// MARK: - Datenmodell (Spec 4). Identisch über alle Verbindungsmodi.

struct TrinkUser: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var tageszielMl: Int

    init(id: Int, name: String, tageszielMl: Int) {
        self.id = id
        self.name = name
        self.tageszielMl = tageszielMl
    }

    init(json: [String: Any]) {
        self.init(
            id: asInt(json["id"]),
            name: asString(json["name"]),
            tageszielMl: asInt(json["tagesziel_ml"])
        )
    }

    var json: [String: Any] {
        ["id": id, "name": name, "tagesziel_ml": tageszielMl]
    }
}

struct TrinkEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let userId: Int
    let getraenk: String
    let mengeMl: Int

    /// Immer UTC. Anzeige erfolgt in Europe/Berlin (Spec 4).
    let createdAt: Date

    /// Lokal erzeugte Einträge bekommen negative IDs, bis der Server eine echte
    /// ID liefert (Spec 4, „Offline-IDs").
    var isPending: Bool { id < 0 }

    init(id: Int, userId: Int, getraenk: String, mengeMl: Int, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.getraenk = getraenk
        self.mengeMl = mengeMl
        self.createdAt = createdAt
    }

    init(json: [String: Any], userId: Int? = nil) {
        self.init(
            id: asInt(json["id"]),
            userId: asInt(json["user_id"], fallback: userId ?? 0),
            getraenk: asString(json["getraenk"]),
            mengeMl: asInt(json["menge_ml"]),
            createdAt: parseServerTime(json["create_time"])
        )
    }

    var json: [String: Any] {
        [
            "id": id,
            "user_id": userId,
            "getraenk": getraenk,
            "menge_ml": mengeMl,
            "create_time": iso8601String(createdAt),
        ]
    }
}

struct TrinkFavorite: Identifiable, Hashable, Sendable {
    let id: Int
    let userId: Int
    let getraenk: String
    let mengeMl: Int

    init(id: Int, userId: Int, getraenk: String, mengeMl: Int) {
        self.id = id
        self.userId = userId
        self.getraenk = getraenk
        self.mengeMl = mengeMl
    }

    init(json: [String: Any], userId: Int? = nil) {
        self.init(
            id: asInt(json["id"]),
            userId: asInt(json["user_id"], fallback: userId ?? 0),
            getraenk: asString(json["getraenk"]),
            mengeMl: asInt(json["menge_ml"])
        )
    }

    var json: [String: Any] {
        ["id": id, "user_id": userId, "getraenk": getraenk, "menge_ml": mengeMl]
    }
}

struct TodayStats: Hashable, Sendable {
    let ml: Int
    let anzahl: Int
    let tageszielMl: Int

    /// `nil`, wenn kein Tagesziel gesetzt ist (Tagesziel 0 = aus).
    let fortschrittPct: Int?
    let zielErreicht: Bool

    static let empty = TodayStats(ml: 0, anzahl: 0, tageszielMl: 0, fortschrittPct: nil, zielErreicht: false)

    init(ml: Int, anzahl: Int, tageszielMl: Int, fortschrittPct: Int?, zielErreicht: Bool) {
        self.ml = ml
        self.anzahl = anzahl
        self.tageszielMl = tageszielMl
        self.fortschrittPct = fortschrittPct
        self.zielErreicht = zielErreicht
    }

    /// Lokale Berechnung aus Summe und Ziel — identisch zum Server.
    init(ml: Int, anzahl: Int, tageszielMl: Int) {
        self.init(
            ml: ml,
            anzahl: anzahl,
            tageszielMl: tageszielMl,
            fortschrittPct: tageszielMl > 0 ? (ml * 100) / tageszielMl : nil,
            zielErreicht: tageszielMl > 0 && ml >= tageszielMl
        )
    }

    init(json: [String: Any]) {
        let ziel = asInt(json["tagesziel_ml"])
        self.init(
            ml: asInt(json["ml"]),
            anzahl: asInt(json["anzahl"]),
            tageszielMl: ziel,
            fortschrittPct: ziel > 0 ? asIntOrNull(json["ziel_fortschritt_pct"]) : nil,
            zielErreicht: asBool(json["ziel_erreicht"])
        )
    }

    var json: [String: Any] {
        [
            "ml": ml,
            "anzahl": anzahl,
            "tagesziel_ml": tageszielMl,
            "ziel_fortschritt_pct": fortschrittPct as Any? ?? NSNull(),
            "ziel_erreicht": zielErreicht,
        ]
    }
}

struct PeriodStats: Hashable, Sendable {
    let ml: Int
    let anzahl: Int

    static let empty = PeriodStats(ml: 0, anzahl: 0)

    init(ml: Int, anzahl: Int) {
        self.ml = ml
        self.anzahl = anzahl
    }

    init(json: [String: Any]?) {
        guard let json else {
            self = .empty
            return
        }
        self.init(ml: asInt(json["ml"]), anzahl: asInt(json["anzahl"]))
    }

    var json: [String: Any] { ["ml": ml, "anzahl": anzahl] }
}

struct StatsBundle: Hashable, Sendable {
    let today: PeriodStats
    let week: PeriodStats
    let month: PeriodStats

    static let empty = StatsBundle(today: .empty, week: .empty, month: .empty)

    init(today: PeriodStats, week: PeriodStats, month: PeriodStats) {
        self.today = today
        self.week = week
        self.month = month
    }

    init(json: [String: Any]) {
        let periods = json["periods"] as? [String: Any] ?? [:]
        self.init(
            today: PeriodStats(json: periods["today"] as? [String: Any]),
            week: PeriodStats(json: periods["week"] as? [String: Any]),
            month: PeriodStats(json: periods["month"] as? [String: Any])
        )
    }

    var json: [String: Any] {
        ["periods": ["today": today.json, "week": week.json, "month": month.json]]
    }
}

/// Vorwahl-Größen sind App-Feature und stehen in jedem Modus sofort bereit
/// (Spec 3.6 / 5).
let vorwahlMengen: [Int] = [125, 200, 250, 300, 330, 500, 750, 1000]

// MARK: - Zeitformate

/// `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` — dasselbe Format, das die Flutter-App in
/// SQLite und Cache geschrieben hat; so bleiben Backups und die vorhandene
/// lokale Datenbank lesbar und Stringvergleiche in SQL funktionieren.
func iso8601String(_ date: Date) -> String {
    Formatters.isoMillis.string(from: date)
}

/// Der Server speichert UTC, liefert sie aber ohne Zonensuffix
/// (`Y-m-d H:i:s`). Ohne Zone wird die Zeit hier explizit als UTC gelesen.
func parseServerTime(_ raw: Any?) -> Date {
    let value = asString(raw).trimmingCharacters(in: .whitespaces)
    if value.isEmpty { return Date() }
    let normalized = value.replacingOccurrences(of: " ", with: "T")
    if let d = Formatters.isoMillisFraction.date(from: normalized) { return d }
    if let d = Formatters.isoPlain.date(from: normalized) { return d }
    if let d = Formatters.utcSeconds.date(from: normalized) { return d }
    if let d = Formatters.utcMinutes.date(from: normalized) { return d }
    return Date()
}

enum Formatters {
    static let utc = TimeZone(identifier: "UTC")!

    static let isoMillis: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    /// Für das Lesen: `Z` oder Offset, mit Sekundenbruchteilen.
    static let isoMillisFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    /// Serverformat ohne Zone: als UTC interpretieren.
    static let utcSeconds: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ss")
    static let utcMinutes: DateFormatter = make("yyyy-MM-dd'T'HH:mm")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }
}
