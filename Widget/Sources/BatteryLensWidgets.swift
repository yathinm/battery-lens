import SwiftUI
import WidgetKit

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

@main
struct BatteryLensWidgetBundle: WidgetBundle {
    var body: some Widget { AllDevicesWidget() }
}
