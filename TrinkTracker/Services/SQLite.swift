import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
/// Erweiterter Fehlercode `SQLITE_CONSTRAINT | (8 << 8)` — als C-Makro nicht in Swift sichtbar.
private let sqliteConstraintUnique: Int32 = SQLITE_CONSTRAINT | (8 << 8)

/// Dünner Wrapper um die SQLite-C-API — genug für den lokalen Modus, ohne
/// Zusatzabhängigkeit. Alle Aufrufe laufen über den `LocalService`-Actor.
final class SQLiteDatabase {
    struct Failure: Error, CustomStringConvertible {
        let code: Int32
        let extended: Int32
        let message: String
        var description: String { message }
        var isUniqueConstraint: Bool { code == SQLITE_CONSTRAINT && extended == sqliteConstraintUnique }
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Datenbank konnte nicht geöffnet werden."
            if let db { sqlite3_close(db) }
            throw Failure(code: SQLITE_ERROR, extended: SQLITE_ERROR, message: message)
        }
        handle = db
    }

    deinit { close() }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    private func failure() -> Failure {
        guard let handle else {
            return Failure(code: SQLITE_MISUSE, extended: SQLITE_MISUSE, message: "Datenbank ist geschlossen.")
        }
        return Failure(
            code: sqlite3_errcode(handle),
            extended: sqlite3_extended_errcode(handle),
            message: String(cString: sqlite3_errmsg(handle))
        )
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer {
        guard let handle else { throw failure() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        for (index, arg) in args.enumerated() {
            let i = Int32(index + 1)
            switch arg {
            case nil: sqlite3_bind_null(stmt, i)
            case is NSNull: sqlite3_bind_null(stmt, i)
            case let v as Int: sqlite3_bind_int64(stmt, i, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, i, v)
            case let v as Int32: sqlite3_bind_int64(stmt, i, Int64(v))
            case let v as Bool: sqlite3_bind_int64(stmt, i, v ? 1 : 0)
            case let v as Double: sqlite3_bind_double(stmt, i, v)
            case let v as String: sqlite3_bind_text(stmt, i, v, -1, sqliteTransient)
            case let v as Data:
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32(v.count), sqliteTransient) }
            default: sqlite3_bind_text(stmt, i, "\(arg!)", -1, sqliteTransient)
            }
        }
        return stmt
    }

    func execute(_ sql: String, _ args: [Any?] = []) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw failure() }
    }

    /// Fügt ein und liefert die neue Zeilen-ID.
    func insert(_ sql: String, _ args: [Any?] = []) throws -> Int {
        try execute(sql, args)
        guard let handle else { throw failure() }
        return Int(sqlite3_last_insert_rowid(handle))
    }

    func query(_ sql: String, _ args: [Any?] = []) throws -> [[String: Any]] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let columnCount = sqlite3_column_count(stmt)
        let names: [String] = (0..<columnCount).map { String(cString: sqlite3_column_name(stmt, $0)) }
        var rows: [[String: Any]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw failure() }
            var row: [String: Any] = [:]
            for i in 0..<columnCount {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[names[Int(i)]] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row[names[Int(i)]] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[names[Int(i)]] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(stmt, i) {
                        row[names[Int(i)]] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i)))
                    }
                default: row[names[Int(i)]] = NSNull()
                }
            }
            rows.append(row)
        }
        return rows
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int {
        get { (try? query("PRAGMA user_version").first?["user_version"] as? Int) ?? 0 }
        set { try? execute("PRAGMA user_version = \(newValue)") }
    }
}
