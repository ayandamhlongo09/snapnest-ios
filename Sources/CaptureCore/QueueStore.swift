import Foundation
import CSQLite

// A private lifetime holder, never exposed outside QueueStore. All access is actor-isolated;
// deinit runs only after the actor releases its sole reference, with no operation in progress.
private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer
    init(_ handle: OpaquePointer) { self.handle = handle }
    deinit { sqlite3_close(handle) }
}

/// One actor owns one SQLite connection. No image enters the network before its transaction commits.
public actor QueueStore {
    public static let maximumItems = 10_000
    public static let maximumBytes = 512 * 1024 * 1024
    public static let maximumImageBytes = 2 * 1024 * 1024
    private let connection: SQLiteConnection
    private var db: OpaquePointer { connection.handle }
    private let itemLimit: Int
    private let byteLimit: Int
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL, itemLimit: Int = QueueStore.maximumItems,
                byteLimit: Int = QueueStore.maximumBytes) throws {
        self.itemLimit = itemLimit; self.byteLimit = byteLimit
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw CaptureError.database("open")
        }
        // DELETE journal avoids orphan WAL management. FULL sync + ACID protects process-kill writes.
        let schema = """
        PRAGMA journal_mode=DELETE;
        PRAGMA synchronous=FULL;
        PRAGMA busy_timeout=5000;
        CREATE TABLE IF NOT EXISTS captures (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, created REAL NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('pending','uploading','uploaded','failed')),
          attempts INTEGER NOT NULL DEFAULT 0, next REAL NOT NULL DEFAULT 0,
          message TEXT, image BLOB, size INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS queue_due ON captures(state,next,created);
        """
        guard sqlite3_exec(connection, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(connection); throw CaptureError.database("schema")
        }
        self.connection = SQLiteConnection(connection!)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CaptureError.database(String(cString: sqlite3_errmsg(db))) }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw CaptureError.database("prepare") }
        return s
    }
    private func bind(_ value: String, _ s: OpaquePointer, _ index: Int32) { sqlite3_bind_text(s, index, value, -1, transient) }
    private func done(_ s: OpaquePointer) throws {
        guard sqlite3_step(s) == SQLITE_DONE else { throw CaptureError.database("write") }
    }
    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try action(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func text(_ s: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(s, column).map { String(cString: $0) } ?? ""
    }
    private func readItem(_ s: OpaquePointer) throws -> CaptureItem {
        guard let id = UUID(uuidString: text(s, 0)), let kind = CaptureKind(rawValue: text(s, 1)),
              let state = UploadState(rawValue: text(s, 3)) else { throw CaptureError.database("invalid row") }
        return CaptureItem(id: id, kind: kind, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 2)),
                           state: state, attempts: Int(sqlite3_column_int(s, 4)),
                           nextAttempt: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
                           message: sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : text(s, 6),
                           byteCount: Int(sqlite3_column_int(s, 7)))
    }
    private var columns: String { "id,kind,created,state,attempts,next,message,size" }

    @discardableResult public func save(image: Data, kind: CaptureKind, id: UUID = UUID()) throws -> UUID {
        guard !image.isEmpty, image.count <= Self.maximumImageBytes else { throw CaptureError.invalidImage }
        return try transaction {
            let summary = try summary()
            // Cap all rows, including receipts shown in history. Never evict a pending capture.
            guard summary.total < itemLimit, summary.bytes + image.count <= byteLimit else { throw CaptureError.full }
            let s = try statement("INSERT INTO captures(id,kind,created,state,image,size) VALUES(?,?,?,'pending',?,?)")
            defer { sqlite3_finalize(s) }
            bind(id.uuidString, s, 1); bind(kind.rawValue, s, 2)
            sqlite3_bind_double(s, 3, Date().timeIntervalSince1970)
            _ = image.withUnsafeBytes { sqlite3_bind_blob(s, 4, $0.baseAddress, Int32(image.count), transient) }
            sqlite3_bind_int(s, 5, Int32(image.count)); try done(s)
            return id
        }
    }
    public func summary() throws -> QueueSummary {
        let s = try statement("SELECT COUNT(*),COALESCE(SUM(state!='uploaded'),0),COALESCE(SUM(state='uploaded'),0),COALESCE(SUM(size),0) FROM captures")
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw CaptureError.database("summary") }
        return QueueSummary(total: Int(sqlite3_column_int(s, 0)), waiting: Int(sqlite3_column_int(s, 1)),
                            uploaded: Int(sqlite3_column_int(s, 2)), bytes: Int(sqlite3_column_int64(s, 3)))
    }
    public func items(limit: Int = 50, offset: Int = 0) throws -> [CaptureItem] {
        let s = try statement("SELECT \(columns) FROM captures ORDER BY created DESC,id LIMIT ? OFFSET ?")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s, 1, Int32(min(max(limit, 1), 100))); sqlite3_bind_int(s, 2, Int32(max(offset, 0)))
        var result: [CaptureItem] = []
        while true {
            let code = sqlite3_step(s)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw CaptureError.database("read") }
            result.append(try readItem(s))
        }
        return result
    }
    public func image(id: UUID) throws -> Data {
        let s = try statement("SELECT image FROM captures WHERE id=?")
        defer { sqlite3_finalize(s) }; bind(id.uuidString, s, 1)
        guard sqlite3_step(s) == SQLITE_ROW, let bytes = sqlite3_column_blob(s, 0) else { throw CaptureError.invalidImage }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 0)))
    }

    public func claim(now: Date, maximumAttempts: Int) throws -> UploadPayload? {
        try transaction {
            let s = try statement("SELECT id,kind,image FROM captures WHERE state IN ('pending','failed') AND attempts<? AND next<=? ORDER BY created,id LIMIT 1")
            defer { sqlite3_finalize(s) }; sqlite3_bind_int(s, 1, Int32(maximumAttempts)); sqlite3_bind_double(s, 2, now.timeIntervalSince1970)
            let code = sqlite3_step(s)
            if code == SQLITE_DONE { return nil }
            guard code == SQLITE_ROW, let id = UUID(uuidString: text(s, 0)), let kind = CaptureKind(rawValue: text(s, 1)),
                  let bytes = sqlite3_column_blob(s, 2) else { throw CaptureError.database("claim") }
            let payload = UploadPayload(id: id, kind: kind, image: Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 2))))
            let u = try statement("UPDATE captures SET state='uploading',attempts=attempts+1,message=NULL WHERE id=?")
            defer { sqlite3_finalize(u) }; bind(id.uuidString, u, 1); try done(u)
            return payload
        }
    }
    public func markUploaded(id: UUID) throws {
        let s = try statement("UPDATE captures SET state='uploaded',image=NULL,size=0,message=NULL WHERE id=? AND state='uploading'")
        defer { sqlite3_finalize(s) }; bind(id.uuidString, s, 1); try done(s)
    }
    public func markFailed(id: UUID, message: String, now: Date, policy: RetryPolicy) throws {
        let s = try statement("UPDATE captures SET state='failed',message=?,next=? WHERE id=? AND state='uploading'")
        defer { sqlite3_finalize(s) }
        let q = try statement("SELECT attempts FROM captures WHERE id=?"); defer { sqlite3_finalize(q) }
        bind(id.uuidString, q, 1)
        guard sqlite3_step(q) == SQLITE_ROW else { throw CaptureError.database("missing attempt") }
        bind(message, s, 1); sqlite3_bind_double(s, 2, now.addingTimeInterval(policy.delay(after: Int(sqlite3_column_int(q, 0)))).timeIntervalSince1970)
        bind(id.uuidString, s, 3); try done(s)
    }
    public func retry(id: UUID) throws {
        let s = try statement("UPDATE captures SET state='pending',attempts=0,next=0,message=NULL WHERE id=? AND state='failed'")
        defer { sqlite3_finalize(s) }; bind(id.uuidString, s, 1); try done(s)
    }
    public func recoverInterrupted() throws {
        try execute("UPDATE captures SET state='pending',attempts=MAX(0,attempts-1),next=0,message=NULL WHERE state='uploading'")
    }
    public func nextDue(maximumAttempts: Int) throws -> Date? {
        let s = try statement("SELECT MIN(next) FROM captures WHERE state IN ('pending','failed') AND attempts<?")
        defer { sqlite3_finalize(s) }; sqlite3_bind_int(s, 1, Int32(maximumAttempts))
        guard sqlite3_step(s) == SQLITE_ROW else { throw CaptureError.database("next") }
        return sqlite3_column_type(s, 0) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 0))
    }
    public func clearUploadedHistory() throws { try execute("DELETE FROM captures WHERE state='uploaded'; VACUUM;") }
    public func integrityCheck() throws -> String {
        let s = try statement("PRAGMA integrity_check"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw CaptureError.database("integrity") }
        return text(s, 0)
    }
}
