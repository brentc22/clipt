import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over a sqlite3 connection. Not thread-safe.
final class Database {
    let handle: OpaquePointer
    private var depth = 0

    init(path: String) throws {
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(path, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let h { sqlite3_close(h) }
            throw SQLiteError(code: rc, message: msg)
        }
        handle = h
        // Wait out a briefly held lock (another connection, a checkpoint) instead of failing at once.
        sqlite3_busy_timeout(h, 2000)
    }

    deinit { sqlite3_close_v2(handle) }

    func error(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }

    func exec(_ sql: String) throws {
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw error(rc) }
    }

    func prepare(_ sql: String) throws -> Statement { try Statement(self, sql) }

    /// Runs a statement that returns no rows.
    func run(_ sql: String, _ binds: [Bind] = []) throws {
        let s = try prepare(sql)
        try s.bind(binds)
        while try s.step() {}
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Nested calls join the outer transaction.
    func transaction<R>(_ body: () throws -> R) throws -> R {
        if depth > 0 { return try body() }
        try exec("BEGIN IMMEDIATE")
        depth = 1
        defer { depth = 0 }
        do {
            let r = try body()
            try exec("COMMIT")
            return r
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}

enum Bind {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case optText(String?)
    case optDouble(Double?)
}

final class Statement {
    private let db: Database
    private var stmt: OpaquePointer?

    init(_ db: Database, _ sql: String) throws {
        self.db = db
        let rc = sqlite3_prepare_v2(db.handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw db.error(rc) }
    }

    deinit { sqlite3_finalize(stmt) }

    func bind(_ binds: [Bind]) throws {
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch b {
            case .null: rc = sqlite3_bind_null(stmt, idx)
            case .int(let v): rc = sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v): rc = sqlite3_bind_text(stmt, idx, v, -1, transient)
            case .optText(let v):
                if let v { rc = sqlite3_bind_text(stmt, idx, v, -1, transient) } else { rc = sqlite3_bind_null(stmt, idx) }
            case .optDouble(let v):
                if let v { rc = sqlite3_bind_double(stmt, idx, v) } else { rc = sqlite3_bind_null(stmt, idx) }
            }
            guard rc == SQLITE_OK else { throw db.error(rc) }
        }
    }

    /// True when a row is available.
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw db.error(rc)
    }

    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
    func optText(_ i: Int32) -> String? { isNull(i) ? nil : text(i) }
}
