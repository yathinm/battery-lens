import AppKit
import BatteryDomain

@MainActor
final class DockCarouselController {
    private var devices: [BatteryDevice] = []
    private var index = 0
    private var timer: Timer?

    func update(devices: [BatteryDevice], enabled: Bool) {
        self.devices = devices.filter { !$0.isHidden && $0.freshness != .expired && $0.batteryLevel != nil }
        guard enabled, !self.devices.isEmpty else {
            stop()
            NSApplication.shared.dockTile.badgeLabel = nil
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.advance() }
            }
        }
        showCurrent()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        index = 0
    }

    private func advance() {
        guard !devices.isEmpty else { return }
        if #available(macOS 12.0, *), ProcessInfo.processInfo.isLowPowerModeEnabled { return }
        index = (index + 1) % devices.count
        showCurrent()
    }

    private func showCurrent() {
        guard !devices.isEmpty else { return }
        index %= devices.count
        let device = devices[index]
        NSApplication.shared.dockTile.badgeLabel = device.batteryLevel.map { "\($0)%" }
        NSApplication.shared.dockTile.display()
    }
}
