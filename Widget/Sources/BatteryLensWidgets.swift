import SwiftUI
import WidgetKit
import AppIntents

private struct Snapshot: Codable {
    let generatedAt: Date
    let devices: [Device]

    struct Device: Codable, Identifiable {
        let id: UUID
        let name: String
        let category: String
        let level: Int?
        let powerState: String
        let freshness: String
        let observedAt: Date
    }
}

private struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

private struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let entry = BatteryEntry(date: Date(), snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }

    private func loadSnapshot() -> Snapshot? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yathinm.BatteryLens"
        ) else { return nil }
        let url = container.appendingPathComponent("widget-snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }
}

private struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Batteries").font(.headline)
                Spacer()
                Image(systemName: "battery.100")
            }
            if let devices = entry.snapshot?.devices, !devices.isEmpty {
                ForEach(Array(devices.prefix(maximumRows))) { device in
                    HStack {
                        Text(device.name).lineLimit(1)
                        Spacer()
                        Text(device.level.map { "\($0)%" } ?? "—")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        if device.powerState == "charging" { Image(systemName: "bolt.fill") }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                if let generatedAt = entry.snapshot?.generatedAt {
                    Text("Updated \(generatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Spacer()
                Text("Open BatteryLens to collect battery information.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
    }

    private var maximumRows: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        case .systemLarge: 9
        default: 4
        }
    }
}

private struct AllDevicesWidget: Widget {
    let kind = "BatteryLens.AllDevices"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Device Batteries")
        .description("See battery levels from BatteryLens.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@available(macOS 14.0, *)
private struct BatteryDeviceEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Battery Device")
    static let defaultQuery = BatteryDeviceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

@available(macOS 14.0, *)
private struct BatteryDeviceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BatteryDeviceEntity] {
        loadDevices().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BatteryDeviceEntity] {
        loadDevices()
    }

    private func loadDevices() -> [BatteryDeviceEntity] {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yathinm.BatteryLens"
        ),
        let data = try? Data(contentsOf: container.appendingPathComponent("widget-snapshot.json")),
        let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return [] }
        return snapshot.devices.map { BatteryDeviceEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

@available(macOS 14.0, *)
private struct SelectBatteryDeviceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Device"
    static let description = IntentDescription("Choose one device to show in this widget.")

    @Parameter(title: "Device")
    var device: BatteryDeviceEntity?

    init() {}
}

@available(macOS 14.0, *)
private struct SingleDeviceProvider: AppIntentTimelineProvider {
    typealias Entry = BatteryEntry
    typealias Intent = SelectBatteryDeviceIntent

    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), snapshot: nil)
    }

    func snapshot(for configuration: SelectBatteryDeviceIntent, in context: Context) async -> BatteryEntry {
        BatteryEntry(date: Date(), snapshot: configuration.device.flatMap { loadSnapshot(for: $0.id) })
    }

    func timeline(for configuration: SelectBatteryDeviceIntent, in context: Context) async -> Timeline<BatteryEntry> {
        let entry = BatteryEntry(date: Date(), snapshot: configuration.device.flatMap { loadSnapshot(for: $0.id) })
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }

    private func loadSnapshot(for identifier: String) -> Snapshot? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yathinm.BatteryLens"
        ),
        let data = try? Data(contentsOf: container.appendingPathComponent("widget-snapshot.json")),
        let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        return Snapshot(generatedAt: snapshot.generatedAt, devices: snapshot.devices.filter { $0.id.uuidString == identifier })
    }
}

@available(macOS 14.0, *)
private struct SingleDeviceWidget: Widget {
    let kind = "BatteryLens.SingleDevice"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectBatteryDeviceIntent.self, provider: SingleDeviceProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Single Device Battery")
        .description("Monitor one selected battery device.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BatteryLensWidgetBundle: WidgetBundle {
    var body: some Widget {
        AllDevicesWidget()
        if #available(macOS 14.0, *) {
            SingleDeviceWidget()
        }
    }
}
