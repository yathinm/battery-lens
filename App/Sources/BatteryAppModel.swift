import AppKit
import BatteryAlerts
import BatteryDiscovery
import BatteryDomain
import BatteryPersistence
import Combine
import Foundation
import WidgetKit

@MainActor
final class BatteryAppModel: ObservableObject {
    @Published private(set) var devices: [BatteryDevice] = []
    @Published private(set) var adapterHealth: [AdapterHealth] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var errorMessage: String?

    let preferences = AppPreferences()
    var onStatusTitleChange: ((String) -> Void)?

    private var repository: SQLiteDeviceRepository?
    private var resolver: DeviceResolver?
    private var scheduler: ScanScheduler?
    private var alertEngine: AlertEngine?
    private var snapshotStore: SnapshotStore?
    private let originMacID: UUID
    private let notificationController = NotificationController()
    private let loginItemController = LoginItemController()
    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var discoverySignature: DiscoverySignature?

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "originMacID"), let id = UUID(uuidString: saved) {
            originMacID = id
        } else {
            let id = UUID()
            originMacID = id
            defaults.set(id.uuidString, forKey: "originMacID")
        }

        preferences.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in self?.preferencesChanged() }
            .store(in: &cancellables)

        notificationController.onSnooze = { [weak self] deviceID in
            Task { await self?.snooze(deviceID: deviceID) }
        }
        configureDependencies()
    }

    var visibleDevices: [BatteryDevice] {
        devices.filter { !$0.isHidden && ($0.freshness != .expired || $0.isPinned) }
    }

    var hiddenDevices: [BatteryDevice] { devices.filter(\.isHidden) }

    func start() {
        notificationController.configure()
        observeSystemEvents()
        Task {
            await scheduler?.start()
            await loadPersistedState()
            refresh(reason: .launch)
        }
        resetRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        Task { await scheduler?.stop() }
    }

    func refresh(reason: RefreshReason) {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        Task {
            guard let scheduler, let resolver else {
                isRefreshing = false
                return
            }
            let observations = await scheduler.refresh(reason: reason)
            let resolved = await resolver.reconcile(observations)
            let health = await scheduler.health()
            await publish(devices: resolved, health: health)
            isRefreshing = false
        }
    }

    func setHidden(_ hidden: Bool, deviceID: UUID) {
        Task {
            await resolver?.setHidden(hidden, deviceID: deviceID)
            let resolved = await resolver?.allDevices() ?? []
            await publish(devices: resolved, health: adapterHealth)
        }
    }

    func setPinned(_ pinned: Bool, deviceID: UUID) {
        Task {
            await resolver?.setPinned(pinned, deviceID: deviceID)
            let resolved = await resolver?.allDevices() ?? []
            await publish(devices: resolved, health: adapterHealth)
        }
    }

    func requestNotificationPermission() {
        notificationController.requestAuthorization()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isLaunchAtLoginEnabled: Bool { loginItemController.isEnabled }

    func eraseDevices() {
        Task {
            guard let repository else { return }
            do {
                try await repository.eraseAll()
                resolver = DeviceResolver(originMacID: originMacID)
                devices = []
                refresh(reason: .manual)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func configureDependencies() {
        do {
            let applicationSupport = try Self.applicationSupportDirectory()
            let repository = try SQLiteDeviceRepository(url: applicationSupport.appendingPathComponent("BatteryLens.sqlite"))
            let snapshotDirectory = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.yathinm.BatteryLens"
            ) ?? applicationSupport
            self.repository = repository
            snapshotStore = try SnapshotStore(directoryURL: snapshotDirectory)

            scheduler = makeScheduler()
            discoverySignature = currentDiscoverySignature
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPersistedState() async {
        guard let repository else { return }
        do {
            let loadedDevices = try await repository.loadDevices()
            let alertStates = try await repository.loadAlertStates()
            resolver = DeviceResolver(existingDevices: loadedDevices, originMacID: originMacID)
            alertEngine = AlertEngine(states: alertStates)
            devices = loadedDevices
            adapterHealth = try await repository.loadAdapterHealth()
            updateStatusTitle()
        } catch {
            errorMessage = error.localizedDescription
            resolver = DeviceResolver(originMacID: originMacID)
            alertEngine = AlertEngine()
        }
    }

    private func publish(devices: [BatteryDevice], health: [AdapterHealth]) async {
        self.devices = devices
        adapterHealth = health
        lastRefresh = Date()
        updateStatusTitle()

        do {
            try await repository?.save(devices: devices)
            try await repository?.save(adapterHealth: health)
            let snapshotDevices = devices.filter { !$0.isHidden && $0.freshness != .expired }.map(WidgetDevice.init)
            try await snapshotStore?.publish(
                WidgetSnapshot(generatedAt: Date(), originMacID: originMacID, devices: snapshotDevices)
            )
            if #available(macOS 11.0, *) { WidgetCenter.shared.reloadAllTimelines() }

            let rule = AlertRule(
                id: Self.globalRuleID,
                lowThreshold: preferences.lowThreshold,
                fullThreshold: preferences.fullThreshold,
                lowEnabled: preferences.lowAlerts,
                fullEnabled: preferences.fullAlerts
            )
            let alerts = await alertEngine?.evaluate(devices: devices, rules: [rule], now: Date()) ?? []
            for alert in alerts { notificationController.deliver(alert, sound: preferences.alertSound) }
            if let states = await alertEngine?.allStates() {
                try await repository?.save(alertStates: states)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func snooze(deviceID: UUID) async {
        await alertEngine?.snooze(deviceID: deviceID, until: Date().addingTimeInterval(1_800))
        if let states = await alertEngine?.allStates() {
            try? await repository?.save(alertStates: states)
        }
    }

    private func updateStatusTitle() {
        guard preferences.showPercentage,
              let level = visibleDevices.first(where: { $0.category == .mac })?.batteryLevel
        else {
            onStatusTitleChange?("")
            return
        }
        onStatusTitleChange?(" \(level)%")
    }

    private func preferencesChanged() {
        updateStatusTitle()
        resetRefreshTimer()
        let signature = currentDiscoverySignature
        guard signature != discoverySignature else { return }
        discoverySignature = signature
        Task { await reconfigureDiscovery() }
    }

    private func reconfigureDiscovery() async {
        let oldScheduler = scheduler
        let replacement = makeScheduler()
        scheduler = replacement
        await oldScheduler?.stop()
        await replacement.start()
        refresh(reason: .manual)
    }

    private func makeScheduler() -> ScanScheduler {
        var adapters: [any DiscoveryAdapter] = [MacPowerAdapter()]
        if preferences.bluetoothAccessories { adapters.append(IORegistryAccessoryAdapter()) }
        if preferences.genericBLE { adapters.append(GenericBLEBatteryAdapter()) }
        if preferences.pairedDevices,
           let helperURL = Bundle.main.url(forAuxiliaryExecutable: "PairedDeviceHelper") {
            adapters.append(PairedDeviceAdapter(executableURL: helperURL))
        }
        return ScanScheduler(adapters: adapters)
    }

    private var currentDiscoverySignature: DiscoverySignature {
        DiscoverySignature(
            accessories: preferences.bluetoothAccessories,
            genericBLE: preferences.genericBLE,
            pairedDevices: preferences.pairedDevices
        )
    }

    private func resetRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = max(30, preferences.refreshInterval)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(reason: .interval) }
        }
        refreshTimer?.tolerance = min(15, interval * 0.1)
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(reason: .wake) }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(reason: .wake) }
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("BatteryLens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let globalRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

private struct DiscoverySignature: Equatable {
    let accessories: Bool
    let genericBLE: Bool
    let pairedDevices: Bool
}
