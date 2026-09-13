import BatteryDomain
import Foundation
import SQLite3

public enum PersistenceError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case statementFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): "Unable to open the BatteryLens database: \(message)"
        case .statementFailed(let message): "A BatteryLens database operation failed: \(message)"
        case .encodingFailed(let message): "Unable to encode BatteryLens data: \(message)"
        case .decodingFailed(let message): "Unable to decode BatteryLens data: \(message)"
        }
    }
}

public actor SQLiteDeviceRepository: DeviceRepository {
    private let handle: DatabaseHandle
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var pointer: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &pointer,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let pointer { sqlite3_close(pointer) }
            throw PersistenceError.openFailed(message)
        }
        handle = DatabaseHandle(pointer)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try Self.execute(
            database: pointer,
            sql: "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL;"
        )
        try Self.execute(
            database: pointer,
            sql: """
                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS records (
                    key TEXT PRIMARY KEY NOT NULL,
                    payload BLOB NOT NULL,
                    updated_at REAL NOT NULL
                );
                INSERT OR IGNORE INTO metadata(key, value) VALUES ('schema_version', '1');
                """
        )
    }

    public func loadDevices() throws -> [BatteryDevice] {
        try load([BatteryDevice].self, key: "devices") ?? []
    }

    public func save(devices: [BatteryDevice]) throws {
        try save(devices, key: "devices")
    }

    public func loadAlertStates() throws -> [AlertState] {
        try load([AlertState].self, key: "alert_states") ?? []
    }

    public func save(alertStates: [AlertState]) throws {
        try save(alertStates, key: "alert_states")
    }

    public func loadAlertRules() throws -> [AlertRule] {
        try load([AlertRule].self, key: "alert_rules") ?? []
    }

    public func save(alertRules: [AlertRule]) throws {
        try save(alertRules, key: "alert_rules")
    }

    public func loadAdapterHealth() throws -> [AdapterHealth] {
        try load([AdapterHealth].self, key: "adapter_health") ?? []
    }

    public func save(adapterHealth: [AdapterHealth]) throws {
        try save(adapterHealth, key: "adapter_health")
    }

    public func eraseAll() throws {
        try Self.execute(database: handle.pointer, sql: "DELETE FROM records;")
    }

    private func load<Value: Decodable>(_ type: Value.Type, key: String) throws -> Value? {
        let sql = "SELECT payload FROM records WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw statementError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, Self.sqliteTransient)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw statementError() }

        let length = Int(sqlite3_column_bytes(statement, 0))
        guard length > 0, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let data = Data(bytes: bytes, count: length)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw PersistenceError.decodingFailed(error.localizedDescription)
        }
    }

    private func save<Value: Encodable>(_ value: Value, key: String) throws {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }

        let sql = """
            INSERT INTO records(key, payload, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw statementError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, Self.sqliteTransient)
        _ = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), Self.sqliteTransient)
        }
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw statementError() }
    }

    private func statementError() -> PersistenceError {
        .statementFailed(String(cString: sqlite3_errmsg(handle.pointer)))
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func execute(database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw PersistenceError.statementFailed(message)
        }
    }
}

private final class DatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}
