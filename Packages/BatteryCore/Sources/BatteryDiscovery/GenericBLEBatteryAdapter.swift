import BatteryDomain
@preconcurrency import CoreBluetooth
import Foundation

public final class GenericBLEBatteryAdapter: DiscoveryAdapter, @unchecked Sendable {
    public let id = "generic-ble-battery"
    private let scanner = BLEBatteryScanner()
    private let state = BLEAdapterState()

    public init() {}

    public func start() async {
        scanner.start()
        await state.setPermission(scanner.permissionState)
    }

    public func stop() async {
        scanner.stop()
    }

    public func scan() async throws -> [DeviceObservation] {
        await state.beginScan()
        do {
            let readings = try await scanner.scan(timeout: 8)
            let now = Date()
            let observations = readings.map { reading in
                DeviceObservation(
                    candidateKey: SourceKey(namespace: id, identifier: reading.identifier.uuidString),
                    adapterID: id,
                    displayName: reading.name,
                    category: .other,
                    values: ObservationValues(batteryLevel: reading.level),
                    quality: 85,
                    observedAt: reading.observedAt,
                    expiresAt: reading.observedAt.addingTimeInterval(600),
                    capabilities: DeviceCapabilities(reportsCharging: false)
                )
            }
            await state.completeScan(at: now)
            return observations
        } catch {
            await state.failScan(error)
            throw error
        }
    }

    public func health() async -> AdapterHealth {
        await state.health(permission: scanner.permissionState, poweredOn: scanner.isPoweredOn)
    }
}

private actor BLEAdapterState {
    private var value = AdapterHealth(adapterID: "generic-ble-battery", permission: .notDetermined)

    func setPermission(_ permission: PermissionState) {
        value.permission = permission
    }

    func beginScan() {
        value.isScanning = true
        value.lastErrorCode = nil
        value.lastErrorDescription = nil
    }

    func completeScan(at date: Date) {
        value.isScanning = false
        value.availability = .available
        value.lastSuccess = date
    }

    func failScan(_ error: Error) {
        value.isScanning = false
        value.lastErrorCode = "ble_scan_failed"
        value.lastErrorDescription = error.localizedDescription
    }

    func health(permission: PermissionState, poweredOn: Bool) -> AdapterHealth {
        value.permission = permission
        value.availability = poweredOn ? .available : .unavailable
        return value
    }
}

private struct BLEBatteryReading: Sendable {
    let identifier: UUID
    let name: String
    let level: Int
    let observedAt: Date
}

private final class BLEBatteryScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.yathinm.BatteryLens.ble", qos: .utility)
    private var central: CBCentralManager!
    private var continuation: CheckedContinuation<[BLEBatteryReading], Error>?
    private var deadline: DispatchWorkItem?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var readings: [UUID: BLEBatteryReading] = [:]
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelCharacteristic = CBUUID(string: "2A19")

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    var permissionState: PermissionState {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unsupported
        }
    }

    var isPoweredOn: Bool { queue.sync { central.state == .poweredOn } }

    func start() {
        queue.async { _ = self.central.state }
    }

    func stop() {
        queue.async { self.finish() }
    }

    func scan(timeout: TimeInterval) async throws -> [BLEBatteryReading] {
        guard permissionState != .denied && permissionState != .restricted else {
            throw DiscoveryError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let existing = self.continuation {
                    existing.resume(throwing: DiscoveryError.cancelled)
                }
                self.continuation = continuation
                self.peripherals.removeAll(keepingCapacity: true)
                self.readings.removeAll(keepingCapacity: true)

                let deadline = DispatchWorkItem { [weak self] in self?.finish() }
                self.deadline = deadline
                self.queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
                self.beginScanningIfPossible()
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        beginScanningIfPossible()
        if central.state == .unauthorized {
            finish(error: DiscoveryError.permissionDenied)
        } else if [.unsupported, .poweredOff].contains(central.state) {
            finish(error: DiscoveryError.unavailable("Bluetooth is unavailable or powered off."))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        guard continuation != nil, peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripherals.removeValue(forKey: peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == batteryService }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([batteryLevelCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
            let characteristic = service.characteristics?.first(where: { $0.uuid == batteryLevelCharacteristic })
        else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { central.cancelPeripheralConnection(peripheral) }
        guard error == nil, let byte = characteristic.value?.first else { return }
        readings[peripheral.identifier] = BLEBatteryReading(
            identifier: peripheral.identifier,
            name: peripheral.name ?? "Bluetooth Device",
            level: min(100, Int(byte)),
            observedAt: Date()
        )
    }

    private func beginScanningIfPossible() {
        guard continuation != nil, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: [batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func finish(error: Error? = nil) {
        deadline?.cancel()
        deadline = nil
        central.stopScan()
        for peripheral in peripherals.values { central.cancelPeripheralConnection(peripheral) }
        peripherals.removeAll(keepingCapacity: true)
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: readings.values.sorted { $0.name < $1.name })
        }
    }
}
