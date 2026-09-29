import WidgetKit
import SwiftUI

struct NextUpEntry: TimelineEntry {
    let date: Date
    let snapshot: NextUpSnapshot?
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry { NextUpEntry(date: .now, snapshot: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(NextUpEntry(date: .now, snapshot: context.isPreview ? Self.sample : NextUpSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let snap = NextUpSnapshot.load()
        // Refresh when each upcoming item starts so "next" always moves forward, and at least hourly.
        var dates = [Date.now]
        dates += (snap?.entries ?? []).map(\.startsAt).filter { $0 > .now }.prefix(10)
        let entries = dates.sorted().map { NextUpEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(Date.now.addingTimeInterval(3600))))
    }

    static let sample = NextUpSnapshot(
        tripName: "Japan 2026", tripStart: .now.addingTimeInterval(86400 * 30), tripEnd: .now.addingTimeInterval(86400 * 44),
        generatedAt: .now,
        entries: [.init(id: UUID(), title: "Meiji Jingu shrine visit", place: "Meiji Jingu, Tokyo", startsAt: .now.addingTimeInterval(7200),
                        timeZoneID: "Asia/Tokyo", symbol: "sparkles", statusLabel: "Planned", isBooked: false)])
}

struct NextUpView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextUpEntry

    private var upcoming: [NextUpSnapshot.Entry] { (entry.entry?.entries ?? []).filter { $0.startsAt >= entry.date.addingTimeInterval(-3600) } }

    var body: some View {
        if let snap = entry.snapshot {
            let upcoming = snap.entries.filter { $0.startsAt >= entry.date.addingTimeInterval(-3600) }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snap.tripName).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    if snap.tripStart > entry.date {
                        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date),
                                                                   to: Calendar.current.startOfDay(for: snap.tripStart)).day ?? 0
                        Text("\(days) days").font(.caption.weight(.bold)).foregroundStyle(.tint)
                    }
                }
                if upcoming.isEmpty {
                    Text("Nothing scheduled").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(upcoming.prefix(family == .systemSmall ? 1 : 3)) { item in row(item) }
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("Open TripTrac to load your trip").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ item: NextUpSnapshot.Entry) -> some View {
        let tz = TimeZone(identifier: item.timeZoneID) ?? .current
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.symbol).foregroundStyle(item.isBooked ? Color.green : Color.orange).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(item.startsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: tz)))
                    .font(.caption).foregroundStyle(.secondary)
                if !item.place.isEmpty && family != .systemSmall { Text(item.place).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

private extension NextUpEntry { var entry: NextUpSnapshot? { snapshot } }

struct TripTracWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TripTracNextUp", provider: NextUpProvider()) { entry in
            NextUpView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("Your trip countdown and what's coming next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TripTracWidgetBundle: WidgetBundle {
    var body: some Widget { TripTracWidget() }
}
