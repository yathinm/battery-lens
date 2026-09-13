import BatteryDomain
import Foundation

public enum RefreshReason: String, Sendable {
    case launch, interval, menuOpened, bluetoothChanged, wake, networkChanged, manual
}

private actor AdapterRunner {
    private let adapter: any DiscoveryAdapter
    private var inFlight: Task<[DeviceObservation], Error>?

    init(adapter: any DiscoveryAdapter) {
        self.adapter = adapter
    }

    func start() async { await adapter.start() }
    func stop() async { await adapter.stop() }
    func health() async -> AdapterHealth { await adapter.health() }

    func scan() async throws -> [DeviceObservation] {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await adapter.scan() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

public actor ScanScheduler {
    private let runners: [String: AdapterRunner]

    public init(adapters: [any DiscoveryAdapter]) {
        runners = Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, AdapterRunner(adapter: $0)) })
    }

    public func start() async {
        await withTaskGroup(of: Void.self) { group in
            for runner in runners.values { group.addTask { await runner.start() } }
        }
    }

    public func stop() async {
        await withTaskGroup(of: Void.self) { group in
            for runner in runners.values { group.addTask { await runner.stop() } }
        }
    }

    public func refresh(adapterIDs: Set<String>? = nil, reason: RefreshReason) async -> [DeviceObservation] {
        let selected = runners.filter { adapterIDs?.contains($0.key) ?? true }.values
        return await withTaskGroup(of: [DeviceObservation].self, returning: [DeviceObservation].self) { group in
            for runner in selected {
                group.addTask { (try? await runner.scan()) ?? [] }
            }
            var observations: [DeviceObservation] = []
            for await result in group { observations.append(contentsOf: result) }
            return observations
        }
    }

    public func health() async -> [AdapterHealth] {
        await withTaskGroup(of: AdapterHealth.self, returning: [AdapterHealth].self) { group in
            for runner in runners.values { group.addTask { await runner.health() } }
            var values: [AdapterHealth] = []
            for await value in group { values.append(value) }
            return values.sorted { $0.adapterID < $1.adapterID }
        }
    }
}
