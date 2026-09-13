import BatteryDomain
import Foundation

public struct DiagnosticRetentionPolicy: Sendable {
    public var operationalDays: Int
    public var errorDays: Int

    public init(operationalDays: Int = 7, errorDays: Int = 14) {
        self.operationalDays = max(1, operationalDays)
        self.errorDays = max(1, errorDays)
    }

    func cutoff(for logClass: DiagnosticLogClass, now: Date) -> Date {
        let days = logClass == .error ? errorDays : operationalDays
        return now.addingTimeInterval(-Double(days) * 86_400)
    }
}

public actor DiagnosticStore {
    private let fileURL: URL
    private var retention: DiagnosticRetentionPolicy
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, retention: DiagnosticRetentionPolicy = .init()) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("diagnostic-events.json")
        self.retention = retention
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func updateRetention(_ retention: DiagnosticRetentionPolicy) {
        self.retention = retention
    }

    public func record(_ event: DiagnosticEvent, now: Date = Date()) throws {
        var events = try load()
        events.append(event)
        try write(purged(events, now: now))
    }

    public func load(now: Date = Date()) throws -> [DiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoded = try decoder.decode([DiagnosticEvent].self, from: Data(contentsOf: fileURL))
        return purged(decoded, now: now)
    }

    public func purge(now: Date = Date()) throws {
        try write(purged(try load(now: now), now: now))
    }

    public func erase() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func purged(_ events: [DiagnosticEvent], now: Date) -> [DiagnosticEvent] {
        events.filter { $0.timestamp >= retention.cutoff(for: $0.logClass, now: now) }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(5_000)
    }

    private func write<S: Sequence>(_ events: S) throws where S.Element == DiagnosticEvent {
        try encoder.encode(Array(events)).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
