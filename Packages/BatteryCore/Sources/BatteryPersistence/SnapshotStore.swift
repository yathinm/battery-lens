import BatteryDomain
import Foundation

public actor SnapshotStore {
    public static let fileName = "widget-snapshot.json"

    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public var fileURL: URL { directoryURL.appendingPathComponent(Self.fileName) }

    public func publish(_ snapshot: WidgetSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func load() throws -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(WidgetSnapshot.self, from: Data(contentsOf: fileURL))
    }
}
