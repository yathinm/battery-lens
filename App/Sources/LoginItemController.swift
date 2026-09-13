import Foundation
import ServiceManagement

enum LoginItemError: Error, LocalizedError {
    case executableUnavailable

    var errorDescription: String? { "BatteryLens could not determine its application executable." }
}

struct LoginItemController {
    private let fileManager: FileManager
    private let launchAgentsDirectory: URL
    private let executableURL: URL?
    private let label = "com.yathinm.BatteryLens.LoginItem"

    init(
        fileManager: FileManager = .default,
        launchAgentsDirectory: URL? = nil,
        executableURL: URL? = Bundle.main.executableURL
    ) {
        self.fileManager = fileManager
        self.launchAgentsDirectory = launchAgentsDirectory
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        self.executableURL = executableURL
    }

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return fileManager.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            return
        }

        if enabled {
            guard let executableURL else { throw LoginItemError.executableUnavailable }
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            let propertyList: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executableURL.path],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: propertyList,
                format: .xml,
                options: 0
            )
            try data.write(to: launchAgentURL, options: [.atomic])
        } else if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }
    }

    private var launchAgentURL: URL { launchAgentsDirectory.appendingPathComponent("\(label).plist") }
}
