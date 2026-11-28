import Foundation
import SQLite3

/// 时间洞察的本机数据库：系统自带的 SQLite（libsqlite3），不加第三方包。
///
/// 文件在 Application Support/<bundle id>/TimeInsights/activity.sqlite，只在本机，
/// 不上传。版本号存在 `PRAGMA user_version`，每升一版在 `TimeInsightsSchema.migrations`
/// 里加一步；比当前版本新的文件（装过更新的版本又退回来）不动它，报错让界面提示，
/// 不覆盖、不用假数据补。清空数据删掉全部记录并压缩文件；卸载时删掉 TimeInsights
/// 文件夹即可。
public enum TimeInsightsSchema {
    public static let currentVersion: Int32 = 1

    /// 第 n 版要执行的语句。只加不改：已经发出去的版本的语句不能再动。
    public static let migrations: [Int32: [String]] = [
        1: [
            """
            CREATE TABLE IF NOT EXISTS sessions(
                id TEXT PRIMARY KEY,
                start_at REAL NOT NULL,
                end_at REAL NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT,
                domain TEXT,
                classification TEXT NOT NULL DEFAULT 'uncategorized',
                source TEXT NOT NULL DEFAULT 'foreground',
                privacy_flags INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start_at)",
            "CREATE INDEX IF NOT EXISTS sessions_end ON sessions(end_at)",
            """
            CREATE TABLE IF NOT EXISTS open_session(
                slot INTEGER PRIMARY KEY CHECK (slot = 0),
                payload TEXT NOT NULL
            )
            """,
        ],
    ]

    public enum Plan: Equatable, Sendable {
        case upToDate
        /// 依次执行这几版。
        case migrate([Int32])
        /// 文件是更新的版本写的，不认。
        case tooNew(Int32)
    }

    /// 从 `version`（新文件是 0）升到 `target` 要走哪几步。
    public static func plan(from version: Int32, to target: Int32 = currentVersion) -> Plan {
        if version > target { return .tooNew(version) }
        if version == target { return .upToDate }
        return .migrate(Array((max(0, version) + 1)...target))
    }
}

public final class TimeInsightsDatabase {
    public enum Failure: Error, Equatable {
        case cannotOpen(Int32)
        case tooNew(Int32)
        case sql(Int32, String)
    }

    public let url: URL
    private var handle: OpaquePointer?

    /// 默认位置。
    public static func defaultURL(bundleID: String = Bundle.main.bundleIdentifier ?? "com.docket-zh.app") -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "TimeInsights", directoryHint: .isDirectory)
            .appending(path: "activity.sqlite")
    }

    /// 打开（没有就建）并升到当前版本。
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw Failure.cannotOpen(code)
        }
        handle = db
        sqlite3_busy_timeout(db, 2000)
        try exec("PRAGMA journal_mode=WAL")
        try migrate()
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: 版本

    public var version: Int32 {
        (try? query("PRAGMA user_version", row: { sqlite3_column_int($0, 0) }).first) ?? 0
    }

    private func migrate() throws {
        switch TimeInsightsSchema.plan(from: version) {
        case .upToDate:
            return
        case .tooNew(let found):
            throw Failure.tooNew(found)
        case .migrate(let steps):
            try transaction {
                for step in steps {
                    for statement in TimeInsightsSchema.migrations[step] ?? [] {
                        try exec(statement)
                    }
                    try exec("PRAGMA user_version = \(step)")
                }
            }
        }
    }

    // MARK: 读写

    /// 写入已经结束的段。同 id 的已经在库里时跳过（崩溃恢复和正常收尾可能给出同一段）。
    public func insert(_ sessions: [ActivitySession]) throws {
        guard !sessions.isEmpty else { return }
        try transaction {
            let sql = """
                INSERT OR IGNORE INTO sessions
                (id, start_at, end_at, bundle_id, app_name, window_title, domain, classification, source, privacy_flags)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            for s in sessions {
                try run(sql) { stmt in
                    bind(stmt, 1, s.id)
                    sqlite3_bind_double(stmt, 2, s.start.timeIntervalSince1970)
                    sqlite3_bind_double(stmt, 3, s.end.timeIntervalSince1970)
                    bind(stmt, 4, s.bundleID)
                    bind(stmt, 5, s.appName)
                    bind(stmt, 6, s.windowTitle)
                    bind(stmt, 7, s.domain)
                    bind(stmt, 8, s.classification.rawValue)
                    bind(stmt, 9, s.source.rawValue)
                    sqlite3_bind_int64(stmt, 10, Int64(s.privacyFlags.rawValue))
                }
            }
        }
    }

    /// 和 `interval` 有重叠的段，按开始时间排。
    public func sessions(overlapping interval: DateInterval) throws -> [ActivitySession] {
        try query("""
            SELECT id, start_at, end_at, bundle_id, app_name, window_title, domain, classification, source, privacy_flags
            FROM sessions WHERE start_at < ? AND end_at > ? ORDER BY start_at
            """, bind: { stmt in
                sqlite3_bind_double(stmt, 1, interval.end.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, interval.start.timeIntervalSince1970)
            }, row: Self.session)
    }

    /// 全部的段（导出用）。
    public func allSessions() throws -> [ActivitySession] {
        try query("""
            SELECT id, start_at, end_at, bundle_id, app_name, window_title, domain, classification, source, privacy_flags
            FROM sessions ORDER BY start_at
            """, row: Self.session)
    }

    public func count() throws -> Int {
        try query("SELECT COUNT(*) FROM sessions", row: { Int(sqlite3_column_int64($0, 0)) }).first ?? 0
    }

    /// 删掉在 `date` 之前就结束的段（留存上限）。
    public func prune(endingBefore date: Date) throws {
        try run("DELETE FROM sessions WHERE end_at < ?") { stmt in
            sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        }
    }

    /// 只删某个 App 的记录（排除一个 App 时可选）。
    public func delete(bundleID: String) throws {
        try run("DELETE FROM sessions WHERE bundle_id = ?") { bind($0, 1, bundleID) }
    }

    /// 清空全部记录和开着的那段，再压缩文件。
    public func deleteAll() throws {
        try transaction {
            try exec("DELETE FROM sessions")
            try exec("DELETE FROM open_session")
        }
        try exec("VACUUM")
    }

    // MARK: 开着的那段（崩溃恢复）

    public func saveOpen(_ segment: TimeInsightsRecorder.Open?) throws {
        guard let segment else {
            try exec("DELETE FROM open_session")
            return
        }
        let data = try JSONEncoder().encode(segment)
        let payload = String(decoding: data, as: UTF8.self)
        try run("INSERT OR REPLACE INTO open_session (slot, payload) VALUES (0, ?)") { bind($0, 1, payload) }
    }

    public func loadOpen() throws -> TimeInsightsRecorder.Open? {
        let payloads = try query("SELECT payload FROM open_session WHERE slot = 0", row: { stmt in
            Self.text(stmt, 0) ?? ""
        })
        guard let payload = payloads.first else { return nil }
        return try? JSONDecoder().decode(TimeInsightsRecorder.Open.self, from: Data(payload.utf8))
    }

    // MARK: SQLite 小工具

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: raw)
    }

    private static func session(_ stmt: OpaquePointer?) -> ActivitySession {
        ActivitySession(id: text(stmt, 0) ?? UUID().uuidString,
                        start: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                        end: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                        bundleID: text(stmt, 3) ?? "",
                        appName: text(stmt, 4) ?? "",
                        windowTitle: text(stmt, 5),
                        domain: text(stmt, 6),
                        classification: TimeInsightsCategory(stored: text(stmt, 7) ?? ""),
                        source: ActivitySource(stored: text(stmt, 8) ?? ""),
                        privacyFlags: ActivityPrivacyFlags(rawValue: Int(sqlite3_column_int64(stmt, 9))))
    }

    private func error(_ code: Int32) -> Failure {
        let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? ""
        return .sql(code, message)
    }

    private func exec(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw error(code) }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard code == SQLITE_OK else {
            sqlite3_finalize(stmt)
            throw error(code)
        }
        return stmt
    }

    /// 执行一条不返回行的语句。
    private func run(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in }) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        let code = sqlite3_step(stmt)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw error(code) }
    }

    private func query<T>(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in },
                          row: (OpaquePointer?) -> T) throws -> [T] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        var out: [T] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_ROW {
                out.append(row(stmt))
            } else if code == SQLITE_DONE {
                break
            } else {
                throw error(code)
            }
        }
        return out
    }
}
