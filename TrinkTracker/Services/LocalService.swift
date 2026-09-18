import Foundation

/// Lokaler Modus (Spec 3.6): SQLite auf dem Gerät, Schema als Spiegel des
/// Servers. **Kein Seeding** — der erste Start ist leer, jede Familie legt
/// Nutzer, Ziele und Favoriten selbst an.
///
/// Datei und Schema sind identisch zur Flutter-Version (`Documents/
/// trinktracker.db`), eine vorhandene Datenbank wird direkt weiterverwendet.
actor LocalService: TrinkEntryService {
    static let schemaVersion = 1
    static let defaultFileName = "trinktracker.db"

    nonisolated let supportsUserManagement = true

    private let path: String
    private var db: SQLiteDatabase?

    /// Standardpfad: der Dokumente-Ordner der App — derselbe Ort, den sqflite
    /// unter iOS verwendet hat.
    static func defaultPath(fileName: String = defaultFileName) -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName).path
    }

    init(path: String = LocalService.defaultPath()) {
        self.path = path
    }

    private func open() throws -> SQLiteDatabase {
        if let db { return db }
        let database: SQLiteDatabase
        do {
            database = try SQLiteDatabase(path: path)
            try database.execute("PRAGMA foreign_keys = ON")
            if database.userVersion < 1 {
                try Self.createSchema(database)
                database.userVersion = Self.schemaVersion
            }
            // Migrationspfad über `user_version`; bislang gibt es nur Version 1.
        } catch {
            throw TrinkError(.server, "Lokale Datenbank konnte nicht geöffnet werden: \(error)")
        }
        db = database
        return database
    }

    private static func createSchema(_ db: SQLiteDatabase) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              tagesziel_ml INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
              getraenk TEXT NOT NULL,
              menge_ml INTEGER NOT NULL,
              create_time TEXT NOT NULL
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_entries_user_time ON entries(user_id, create_time)")
        try db.execute("""
            CREATE TABLE IF NOT EXISTS favoriten (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
              getraenk TEXT NOT NULL,
              menge_ml INTEGER NOT NULL,
              UNIQUE(user_id, getraenk, menge_ml)
            )
            """)
    }

    /// SQLite-Fehler in App-Fehler übersetzen; UNIQUE entspricht dem 409 des Servers.
    private func wrap<T>(_ duplicateMessage: String? = nil, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let failure as SQLiteDatabase.Failure {
            if failure.isUniqueConstraint, let duplicateMessage {
                throw TrinkError(.validation, duplicateMessage)
            }
            throw TrinkError(.server, "Datenbankfehler: \(failure.message)")
        }
    }

    // MARK: Lesen

    func getUsers() async throws -> [TrinkUser] {
        let db = try open()
        return try wrap { try db.query("SELECT * FROM users ORDER BY name COLLATE NOCASE") }
            .map(TrinkUser.init(json:))
    }

    func getEntries(userId: Int, limit: Int) async throws -> [TrinkEntry] {
        let db = try open()
        let rows = try wrap {
            try db.query(
                "SELECT * FROM entries WHERE user_id = ? ORDER BY create_time DESC, id DESC LIMIT ?",
                [userId, min(max(limit, 1), 500)]
            )
        }
        return rows.map { TrinkEntry(json: $0, userId: userId) }
    }

    private func sumSince(_ db: SQLiteDatabase, userId: Int, sinceUtc: Date) throws -> PeriodStats {
        let rows = try wrap {
            try db.query(
                "SELECT COALESCE(SUM(menge_ml), 0) AS ml, COUNT(*) AS anzahl FROM entries WHERE user_id = ? AND create_time >= ?",
                [userId, iso8601String(sinceUtc)]
            )
        }
        let row = rows.first ?? [:]
        return PeriodStats(ml: asInt(row["ml"]), anzahl: asInt(row["anzahl"]))
    }

    private func tagesziel(_ db: SQLiteDatabase, userId: Int) throws -> Int {
        let rows = try wrap { try db.query("SELECT tagesziel_ml FROM users WHERE id = ? LIMIT 1", [userId]) }
        guard let row = rows.first else {
            throw TrinkError(.validation, "Nutzer \(userId) existiert nicht.")
        }
        return asInt(row["tagesziel_ml"])
    }

    func getToday(userId: Int) async throws -> TodayStats {
        let db = try open()
        let now = Date()
        let today = try sumSince(db, userId: userId, sinceUtc: BerlinTime.dayStartUtc(now))
        let ziel = try tagesziel(db, userId: userId)
        return TodayStats(ml: today.ml, anzahl: today.anzahl, tageszielMl: ziel)
    }

    func getStats(userId: Int) async throws -> StatsBundle {
        let db = try open()
        let now = Date()
        // Laufende Woche ab Montag, laufender Monat ab dem Ersten — Berliner Grenzen.
        return StatsBundle(
            today: try sumSince(db, userId: userId, sinceUtc: BerlinTime.dayStartUtc(now)),
            week: try sumSince(db, userId: userId, sinceUtc: BerlinTime.weekStartUtc(now)),
            month: try sumSince(db, userId: userId, sinceUtc: BerlinTime.monthStartUtc(now))
        )
    }

    func getFavorites(userId: Int) async throws -> [TrinkFavorite] {
        let db = try open()
        let rows = try wrap {
            try db.query("SELECT * FROM favoriten WHERE user_id = ? ORDER BY getraenk COLLATE NOCASE, menge_ml", [userId])
        }
        return rows.map { TrinkFavorite(json: $0, userId: userId) }
    }

    // MARK: Schreiben

    func createEntry(userId: Int, getraenk: String, mengeMl: Int, createTime: Date?) async throws -> TrinkEntry {
        let db = try open()
        let drink = try TrinkValidation.getraenk(getraenk)
        let menge = try TrinkValidation.menge(mengeMl)
        let when = try TrinkValidation.createTime(createTime ?? Date())
        let id = try wrap {
            try db.insert(
                "INSERT INTO entries (user_id, getraenk, menge_ml, create_time) VALUES (?, ?, ?, ?)",
                [userId, drink, menge, iso8601String(when)]
            )
        }
        return TrinkEntry(id: id, userId: userId, getraenk: drink, mengeMl: menge, createdAt: when)
    }

    func createFavorite(userId: Int, getraenk: String, mengeMl: Int) async throws -> TrinkFavorite {
        let db = try open()
        let drink = try TrinkValidation.getraenk(getraenk)
        let menge = try TrinkValidation.menge(mengeMl)
        let id = try wrap("Diesen Favoriten gibt es schon.") {
            try db.insert("INSERT INTO favoriten (user_id, getraenk, menge_ml) VALUES (?, ?, ?)", [userId, drink, menge])
        }
        return TrinkFavorite(id: id, userId: userId, getraenk: drink, mengeMl: menge)
    }

    func setTagesziel(userId: Int, ml: Int) async throws {
        let db = try open()
        let ziel = try TrinkValidation.tagesziel(ml)
        try wrap { try db.execute("UPDATE users SET tagesziel_ml = ? WHERE id = ?", [ziel, userId]) }
    }

    func deleteEntry(id: Int) async throws {
        let db = try open()
        try wrap { try db.execute("DELETE FROM entries WHERE id = ?", [id]) }
    }

    func undoLast(userId: Int) async throws {
        let db = try open()
        let rows = try wrap {
            try db.query("SELECT id FROM entries WHERE user_id = ? ORDER BY create_time DESC, id DESC LIMIT 1", [userId])
        }
        guard let row = rows.first else {
            throw TrinkError(.validation, "Es gibt keinen Eintrag zum Rückgängigmachen.")
        }
        try wrap { try db.execute("DELETE FROM entries WHERE id = ?", [asInt(row["id"])]) }
    }

    func createUser(name: String) async throws -> TrinkUser {
        let db = try open()
        let clean = try TrinkValidation.userName(name)
        let id = try wrap("Diesen Namen gibt es schon.") {
            try db.insert("INSERT INTO users (name, tagesziel_ml) VALUES (?, 0)", [clean])
        }
        return TrinkUser(id: id, name: clean, tageszielMl: 0)
    }

    func renameUser(userId: Int, name: String) async throws {
        let db = try open()
        let clean = try TrinkValidation.userName(name)
        try wrap("Diesen Namen gibt es schon.") {
            try db.execute("UPDATE users SET name = ? WHERE id = ?", [clean, userId])
        }
    }

    func deleteUser(userId: Int) async throws {
        let db = try open()
        try wrap { try db.execute("DELETE FROM users WHERE id = ?", [userId]) }
    }

    func deleteFavorite(id: Int) async throws {
        let db = try open()
        try wrap { try db.execute("DELETE FROM favoriten WHERE id = ?", [id]) }
    }

    func testConnection() async throws -> Int {
        try await getUsers().count
    }

    // MARK: Backup

    /// Alle Daten als JSON — Grundlage für Backup/Export und Modus-Wechsel.
    /// Format identisch zur Flutter-App, Backups sind in beide Richtungen lesbar.
    func exportAll() async throws -> [String: Any] {
        let db = try open()
        return try wrap {
            [
                "schema": Self.schemaVersion,
                "exported_at": iso8601String(Date()),
                "users": try db.query("SELECT * FROM users"),
                "entries": try db.query("SELECT * FROM entries"),
                "favoriten": try db.query("SELECT * FROM favoriten"),
            ]
        }
    }

    /// Import ersetzt den lokalen Bestand vollständig (in einer Transaktion).
    func importAll(_ data: [String: Any]) async throws {
        let db = try open()
        func rows(_ key: String) -> [[String: Any]] { jsonObjects(data, key) }
        try wrap {
            try db.transaction {
                try db.execute("DELETE FROM entries")
                try db.execute("DELETE FROM favoriten")
                try db.execute("DELETE FROM users")
                for row in rows("users") {
                    try db.execute(
                        "INSERT INTO users (id, name, tagesziel_ml) VALUES (?, ?, ?)",
                        [asInt(row["id"]), asString(row["name"]), asInt(row["tagesziel_ml"])]
                    )
                }
                for row in rows("entries") {
                    try db.execute(
                        "INSERT INTO entries (id, user_id, getraenk, menge_ml, create_time) VALUES (?, ?, ?, ?, ?)",
                        [asInt(row["id"]), asInt(row["user_id"]), asString(row["getraenk"]), asInt(row["menge_ml"]),
                         iso8601String(parseServerTime(row["create_time"]))]
                    )
                }
                for row in rows("favoriten") {
                    try db.execute(
                        "INSERT INTO favoriten (id, user_id, getraenk, menge_ml) VALUES (?, ?, ?, ?)",
                        [asInt(row["id"]), asInt(row["user_id"]), asString(row["getraenk"]), asInt(row["menge_ml"])]
                    )
                }
            }
        }
    }

    func dispose() async {
        db?.close()
        db = nil
    }
}
