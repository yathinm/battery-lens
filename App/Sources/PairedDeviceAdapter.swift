import BatteryDiscovery
import BatteryDomain
import Foundation

actor PairedDeviceAdapter: DiscoveryAdapter {
    nonisolated let id = "paired-apple-devices"
    private let executableURL: URL
    private var currentHealth = AdapterHealth(adapterID: "paired-apple-devices")

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func start() {}
    func stop() {}
    func health() -> AdapterHealth { currentHealth }

    func scan() async throws -> [DeviceObservation] {
        currentHealth.isScanning = true
        defer { currentHealth.isScanning = false }

        let request = PairedDeviceRequest(schemaVersion: 1, command: "list")
        let input = try JSONEncoder().encode(request)
        let result = try await run(input: input, timeout: 12)
        guard result.count <= 1_048_576 else {
            throw DiscoveryError.malformedData("helper output exceeded one megabyte")
        }

        let response = try JSONDecoder().decode(PairedDeviceResponse.self, from: result)
        guard response.schemaVersion == 1 else { throw DiscoveryError.incompatibleVersion(response.schemaVersion) }
        let now = Date()
        currentHealth.lastSuccess = now
        currentHealth.availability = response.sourceAvailable ? .available : .unavailable
        currentHealth.lastErrorCode = response.errorCode
        currentHealth.lastErrorDescription = response.errorMessage

        return response.devices.map { device in
            DeviceObservation(
                candidateKey: SourceKey(namespace: id, identifier: device.identifier),
                adapterID: id,
                displayName: device.name,
                category: device.category == "tablet" ? .tablet : .phone,
                model: device.model,
                values: ObservationValues(
                    batteryLevel: device.batteryLevel,
                    powerState: device.isCharging.map { $0 ? .charging : .discharging }
                ),
                quality: 95,
                observedAt: now,
                expiresAt: now.addingTimeInterval(180),
                capabilities: DeviceCapabilities(reportsCharging: device.isCharging != nil)
            )
        }
    }

    private func run(input: Data, timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [executableURL] in
                let process = Process()
                process.executableURL = executableURL
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                try process.run()
                inputPipe.fileHandleForWriting.write(input)
                try inputPipe.fileHandleForWriting.close()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(decoding: errorData, as: UTF8.self)
                    throw DiscoveryError.unavailable(message.isEmpty ? "The paired-device helper failed." : message)
                }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw DiscoveryError.timeout
            }
            guard let result = try await group.next() else { throw DiscoveryError.unavailable("No helper result.") }
            group.cancelAll()
            return result
        }
    }
}

private struct PairedDeviceRequest: Codable, Sendable {
    let schemaVersion: Int
    let command: String
}

private struct PairedDeviceResponse: Codable, Sendable {
    let schemaVersion: Int
    let sourceAvailable: Bool
    let devices: [PairedDevice]
    let errorCode: String?
    let errorMessage: String?
}

private struct PairedDevice: Codable, Sendable {
    let identifier: String
    let name: String
    let model: String?
    let category: String
    let batteryLevel: Int?
    let isCharging: Bool?
}
