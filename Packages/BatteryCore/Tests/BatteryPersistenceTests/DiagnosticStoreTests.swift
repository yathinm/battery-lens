import BatteryDomain
import BatteryPersistence
import Foundation
import Testing

@Test func diagnosticStoreAppliesClassSpecificRetention() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try DiagnosticStore(
        directoryURL: directory,
        retention: DiagnosticRetentionPolicy(operationalDays: 1, errorDays: 14)
    )
    let now = Date(timeIntervalSince1970: 2_000_000)
    try await store.record(
        DiagnosticEvent(timestamp: now.addingTimeInterval(-2 * 86_400), logClass: .operational, code: "old", summary: "Old"),
        now: now
    )
    try await store.record(
        DiagnosticEvent(timestamp: now.addingTimeInterval(-2 * 86_400), logClass: .error, code: "error", summary: "Error"),
        now: now
    )

    let events = try await store.load(now: now)
    #expect(events.map(\.code) == ["error"])
}
