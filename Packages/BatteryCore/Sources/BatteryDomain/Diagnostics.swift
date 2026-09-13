import Foundation

public enum DiagnosticLogClass: String, Codable, Sendable {
    case operational, error
}

public struct DiagnosticEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let logClass: DiagnosticLogClass
    public let adapterID: String?
    public let code: String
    public let summary: String
    public let durationMilliseconds: Int?
    public let recovered: Bool?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        logClass: DiagnosticLogClass,
        adapterID: String? = nil,
        code: String,
        summary: String,
        durationMilliseconds: Int? = nil,
        recovered: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.logClass = logClass
        self.adapterID = adapterID
        self.code = code
        self.summary = summary
        self.durationMilliseconds = durationMilliseconds
        self.recovered = recovered
    }
}
