import Foundation

private struct Request: Codable {
    let schemaVersion: Int
    let command: String
}

private struct Response: Codable {
    let schemaVersion: Int
    let sourceAvailable: Bool
    let devices: [Device]
    let errorCode: String?
    let errorMessage: String?
}

private struct Device: Codable {
    let identifier: String
    let name: String
    let model: String?
    let category: String
    let batteryLevel: Int?
    let isCharging: Bool?
}

private enum HelperError: Error {
    case invalidRequest
    case unsupportedSchema
    case unsupportedCommand
    case dependencyUnavailable
    case commandFailed(String)
}

private func executable(named name: String) -> URL? {
    let paths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/opt/local/bin/\(name)",
    ]
    return paths.lazy.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
}

private func run(_ executable: URL, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw HelperError.commandFailed(message)
    }
    return String(decoding: data, as: UTF8.self)
}

private func parseKeyValues(_ text: String) -> [String: String] {
    Dictionary(uniqueKeysWithValues: text.split(whereSeparator: \.isNewline).compactMap { line in
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
    })
}

private func collectDevices() throws -> [Device] {
    guard let idTool = executable(named: "idevice_id"), let infoTool = executable(named: "ideviceinfo") else {
        throw HelperError.dependencyUnavailable
    }
    let identifiers = try run(idTool, arguments: ["-l"]).split(whereSeparator: \.isNewline).map(String.init)
    return identifiers.compactMap { identifier in
        guard let generalText = try? run(infoTool, arguments: ["-u", identifier]),
              let batteryText = try? run(infoTool, arguments: ["-u", identifier, "-q", "com.apple.mobile.battery"])
        else { return nil }
        let general = parseKeyValues(generalText)
        let battery = parseKeyValues(batteryText)
        let model = general["ProductType"]
        let category = model?.lowercased().contains("ipad") == true ? "tablet" : "phone"
        let level = battery["BatteryCurrentCapacity"].flatMap(Int.init)
        let charging = battery["BatteryIsCharging"].map { ["true", "yes", "1"].contains($0.lowercased()) }
        return Device(
            identifier: identifier,
            name: general["DeviceName"] ?? (category == "tablet" ? "iPad" : "iPhone"),
            model: model,
            category: category,
            batteryLevel: level,
            isCharging: charging
        )
    }
}

private let response: Response
do {
    let requestData = FileHandle.standardInput.readDataToEndOfFile()
    guard let request = try? JSONDecoder().decode(Request.self, from: requestData) else {
        throw HelperError.invalidRequest
    }
    guard request.schemaVersion == 1 else { throw HelperError.unsupportedSchema }
    guard request.command == "list" else { throw HelperError.unsupportedCommand }
    response = Response(
        schemaVersion: 1,
        sourceAvailable: true,
        devices: try collectDevices(),
        errorCode: nil,
        errorMessage: nil
    )
} catch HelperError.dependencyUnavailable {
    response = Response(
        schemaVersion: 1,
        sourceAvailable: false,
        devices: [],
        errorCode: "paired_device_tools_unavailable",
        errorMessage: "Paired-device support requires compatible signed device tools in the application bundle."
    )
} catch {
    response = Response(
        schemaVersion: 1,
        sourceAvailable: false,
        devices: [],
        errorCode: "paired_device_query_failed",
        errorMessage: String(describing: error)
    )
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
if let data = try? encoder.encode(response) {
    FileHandle.standardOutput.write(data)
} else {
    FileHandle.standardError.write(Data("Unable to encode helper response.".utf8))
    exit(1)
}
