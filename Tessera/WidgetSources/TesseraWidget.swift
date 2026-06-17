import WidgetKit
import SwiftUI

/// Timeline entry: a snapshot of watchlist odds the app wrote to the App Group.
struct OddsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the App Group snapshot the main app publishes after each refresh. The
/// widget process can't open a socket, so it shows the last odds the app stored
/// and refreshes on a fixed cadence as a fallback (the app also pokes it via
/// `WidgetCenter.reloadAllTimelines()` whenever fresh odds arrive).
struct OddsProvider: TimelineProvider {
    func placeholder(in context: Context) -> OddsEntry {
        OddsEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (OddsEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OddsEntry>) -> Void) {
        let entry = currentEntry()
        // Fallback refresh in ~20 min if the app isn't running to push updates.
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> OddsEntry {
        let snapshot = AppGroup.read(WidgetSnapshot.self, from: AppGroup.widgetSnapshotURL)
            ?? .placeholder
        return OddsEntry(date: .now, snapshot: snapshot)
    }
}

struct TesseraWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OddsEntry

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tessera")
                    .font(.caption.weight(.bold))
                Spacer()
                if entry.snapshot.updated != .distantPast {
                    Text(entry.snapshot.updated, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            ForEach(entry.snapshot.outcomes.prefix(rowLimit)) { outcome in
                HStack(spacing: 8) {
                    Text(outcome.title)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(outcome.percent)%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tint(outcome.percent))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.background, for: .widget)
    }

    /// Green when likely, red when unlikely, neutral in the middle.
    private func tint(_ percent: Int) -> Color {
        switch percent {
        case ..<35: return .red
        case 65...: return .green
        default: return .primary
        }
    }
}

struct TesseraWidget: Widget {
    let kind = "TesseraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OddsProvider()) { entry in
            TesseraWidgetView(entry: entry)
        }
        .configurationDisplayName("Tessera Odds")
        .description("Live Kalshi market odds at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TesseraWidgetBundle: WidgetBundle {
    var body: some Widget {
        TesseraWidget()
    }
}
