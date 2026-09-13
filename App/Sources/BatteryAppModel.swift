import AppKit
import BatteryAlerts
import BatteryDiscovery
import BatteryDomain
import BatteryPersistence
import BatteryPeers
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
    @Published private(set) var nearcastCode: String?
    @Published private(set) var trustedPeers: [TrustedPeer] = []

    let preferences = AppPreferences()
    var onStatusTitleChange: ((String) -> Void)?

    private var repository: SQLiteDeviceRepository?
    private var resolver: DeviceResolver?
    private var scheduler: ScanScheduler?
    private var alertEngine: AlertEngine?
    private var snapshotStore: SnapshotStore?
    private var diagnosticStore: DiagnosticStore?
    private let originMacID: UUID
    private let notificationController = NotificationController()
    private let loginItemController = LoginItemController()
    private let keychain = KeychainSecretStore()
    private let nearcastService: NearcastService
    private var remoteDevicesByMac: [UUID: [BatteryDevice]] = [:]
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
        nearcastService = NearcastService(localID: originMacID)

        preferences.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in self?.preferencesChanged() }
            .store(in: &cancellables)

        notificationController.onSnooze = { [weak self] deviceID in
            Task { await self?.snooze(deviceID: deviceID) }
        }
        configureDependencies()
        configureNearcastCallbacks()
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
            await restoreNearcastIfEnabled()
            refresh(reason: .launch)
        }
        resetRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        Task { await scheduler?.stop() }
        Task { await nearcastService.stop() }
    }

    func refresh(reason: RefreshReason) {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        let startedAt = Date()
        Task {
            guard let scheduler, let resolver else {
                isRefreshing = false
                return
            }
            let observations = await scheduler.refresh(reason: reason)
            let resolved = await resolver.reconcile(observations)
            let health = await scheduler.health()
            await publish(devices: resolved, health: health)
            let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
            try? await diagnosticStore?.record(
                DiagnosticEvent(
                    logClass: .operational,
                    code: "refresh_\(reason.rawValue)",
                    summary: "Completed \(reason.rawValue) refresh across \(health.count) sources.",
                    durationMilliseconds: duration
                )
            )
            for item in health where item.lastErrorCode != nil {
                try? await diagnosticStore?.record(
                    DiagnosticEvent(
                        logClass: .error,
                        adapterID: item.adapterID,
                        code: item.lastErrorCode ?? "adapter_error",
                        summary: item.lastErrorDescription ?? "The source reported an error."
                    )
                )
            }
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

    func restoreAllHiddenDevices() {
        Task {
            for device in hiddenDevices { await resolver?.setHidden(false, deviceID: device.id) }
            let resolved = await resolver?.allDevices() ?? []
            await publish(devices: resolved, health: adapterHealth)
        }
    }

    func eraseDiagnostics() {
        Task {
            do { try await diagnosticStore?.erase() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func exportDiagnostics(to url: URL) {
        Task {
            do {
                let events = try await diagnosticStore?.load() ?? []
                try DiagnosticExporter.write(
                    to: url,
                    preferences: preferences,
                    health: adapterHealth,
                    devices: devices,
                    events: events
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createNearcastGroup() {
        Task {
            do {
                let secret = try NearcastSecret.generate()
                try keychain.save(secret.data, account: Self.nearcastKeychainAccount)
                nearcastCode = secret.code
                preferences.localNetworkSharing = true
                await nearcastService.start(secret: secret, displayName: Host.current().localizedName ?? "Mac")
                await broadcastCurrentSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func joinNearcastGroup(code: String) {
        Task {
            do {
                let secret = try NearcastSecret(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
                try keychain.save(secret.data, account: Self.nearcastKeychainAccount)
                nearcastCode = secret.code
                preferences.localNetworkSharing = true
                await nearcastService.start(secret: secret, displayName: Host.current().localizedName ?? "Mac")
                await broadcastCurrentSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func disableNearcast() {
        preferences.localNetworkSharing = false
        remoteDevicesByMac.removeAll()
        devices = devices.filter { $0.originMacID == originMacID }
        trustedPeers = []
        nearcastCode = nil
        try? keychain.delete(account: Self.nearcastKeychainAccount)
        Task { await nearcastService.stop() }
    }

    func revokePeer(_ peer: TrustedPeer) {
        Task {
            do {
                let replacement = try NearcastSecret.generate()
                try keychain.save(replacement.data, account: Self.nearcastKeychainAccount)
                nearcastCode = replacement.code
                remoteDevicesByMac.removeAll()
                devices = devices.filter { $0.originMacID == originMacID }
                trustedPeers = []
                await nearcastService.start(secret: replacement, displayName: Host.current().localizedName ?? "Mac")
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
            diagnosticStore = try DiagnosticStore(
                directoryURL: applicationSupport.appendingPathComponent("Diagnostics", isDirectory: true),
                retention: DiagnosticRetentionPolicy(operationalDays: preferences.diagnosticRetentionDays)
            )

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
            let localDevices = loadedDevices.filter { $0.originMacID == originMacID }
            let alertStates = try await repository.loadAlertStates()
            resolver = DeviceResolver(existingDevices: localDevices, originMacID: originMacID)
            alertEngine = AlertEngine(states: alertStates)
            devices = localDevices
            adapterHealth = try await repository.loadAdapterHealth()
            updateStatusTitle()
        } catch {
            errorMessage = error.localizedDescription
            resolver = DeviceResolver(originMacID: originMacID)
            alertEngine = AlertEngine()
        }
    }

    private func publish(devices: [BatteryDevice], health: [AdapterHealth]) async {
        self.devices = devices + remoteDevicesByMac.values.flatMap { $0 }
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
            if preferences.localNetworkSharing {
                try await nearcastService.broadcast(
                    WidgetSnapshot(
                        generatedAt: Date(),
                        originMacID: originMacID,
                        devices: devices.filter { !$0.isHidden && $0.freshness != .expired }.map(WidgetDevice.init)
                    )
                )
            }
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
        Task {
            await diagnosticStore?.updateRetention(
                DiagnosticRetentionPolicy(operationalDays: preferences.diagnosticRetentionDays)
            )
            try? await diagnosticStore?.purge()
        }
        let signature = currentDiscoverySignature
        guard signature != discoverySignature else { return }
        discoverySignature = signature
        Task { await reconfigureDiscovery() }
    }

    private func configureNearcastCallbacks() {
        Task {
            await nearcastService.setSnapshotHandler { [weak self] snapshot, peerName in
                Task { @MainActor in self?.receiveRemoteSnapshot(snapshot, peerName: peerName) }
            }
            await nearcastService.setPeersHandler { [weak self] peers in
                Task { @MainActor in self?.trustedPeers = peers }
            }
        }
    }

    private func restoreNearcastIfEnabled() async {
        guard preferences.localNetworkSharing else { return }
        do {
            guard let data = try keychain.load(account: Self.nearcastKeychainAccount) else {
                preferences.localNetworkSharing = false
                return
            }
            let secret = try NearcastSecret(data: data)
            nearcastCode = secret.code
            await nearcastService.start(secret: secret, displayName: Host.current().localizedName ?? "Mac")
        } catch {
            preferences.localNetworkSharing = false
            errorMessage = error.localizedDescription
        }
    }

    private func broadcastCurrentSnapshot() async {
        let local = devices.filter { $0.originMacID == originMacID && !$0.isHidden && $0.freshness != .expired }
        try? await nearcastService.broadcast(
            WidgetSnapshot(generatedAt: Date(), originMacID: originMacID, devices: local.map(WidgetDevice.init))
        )
    }

    private func receiveRemoteSnapshot(_ snapshot: WidgetSnapshot, peerName: String) {
        let now = Date()
        let remote = snapshot.devices.map { item in
            let source = SourceKey(namespace: "nearcast.\(snapshot.originMacID.uuidString)", identifier: item.id.uuidString)
            let age = now.timeIntervalSince(item.observedAt)
            let freshness: Freshness = age >= 1_200 ? .expired : age >= 600 ? .stale : age >= 90 ? .aging : item.freshness
            return BatteryDevice(
                id: item.id,
                sourceKeys: [source],
                displayName: item.name,
                category: item.category,
                batteryLevel: item.level,
                powerState: item.powerState,
                originMacID: snapshot.originMacID,
                observedAt: item.observedAt,
                receivedAt: now,
                freshness: freshness,
                preferredSource: source
            )
        }
        remoteDevicesByMac[snapshot.originMacID] = remote
        let local = devices.filter { $0.originMacID == originMacID }
        devices = local + remoteDevicesByMac.values.flatMap { $0 }
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
    private static let nearcastKeychainAccount = "nearcast.group-secret"
}

private struct DiscoverySignature: Equatable {
    let accessories: Bool
    let genericBLE: Bool
    let pairedDevices: Bool
}
