import SwiftUI
import SwiftData

/// Share a trip as an image card, plain text, a calendar file, or a full JSON backup.
struct ShareTripView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var who: UUID?
    @State private var image: Image?
    @State private var icsURL: URL?
    @State private var backupURL: URL?

    private var snapshot: TripSnapshot { TripSnapshot(trip: trip) }
    private var text: String { ItineraryExporter.text(snapshot, travelerID: who) }

    var body: some View {
        NavigationStack {
            Form {
                if !trip.allTravelers.isEmpty {
                    Section {
                        Picker("Plan for", selection: $who) {
                            Text("Everyone").tag(UUID?.none)
                            ForEach(trip.allTravelers) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } footer: { Text("Text and calendar exports include only this traveler's items plus anything for the whole group.") }
                }
                Section("SHARE") {
                    if let image {
                        ShareLink(item: image, preview: SharePreview(trip.name, image: image)) { Label("Summary card (image)", systemImage: "photo") }
                    }
                    ShareLink(item: text, subject: Text(trip.name)) { Label("Itinerary as text", systemImage: "text.alignleft") }
                    if let icsURL { ShareLink(item: icsURL) { Label("Calendar file (.ics)", systemImage: "calendar.badge.plus") } }
                }
                Section {
                    if let backupURL { ShareLink(item: backupURL) { Label("Backup file (JSON)", systemImage: "externaldrive") } }
                } header: { Text("BACKUP") } footer: {
                    Text("Everything about this trip, including confirmation numbers. Restore it from Trips → + → Import file. Keep it private.")
                }
            }
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: who) { await prepare() }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor private func prepare() async {
        let snap = snapshot
        let renderer = ImageRenderer(content: ShareCardView(trip: trip, snapshot: snap).frame(width: 360).padding(12).background(Color(.systemBackground)))
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
        let dir = FileManager.default.temporaryDirectory
        let safe = trip.name.replacingOccurrences(of: "/", with: "-")
        let ics = dir.appendingPathComponent("\(safe).ics")
        try? ICSExporter.make(snap, travelerID: who).write(to: ics, atomically: true, encoding: .utf8)
        icsURL = ics
        let backup = dir.appendingPathComponent("\(safe) backup.json")
        if let data = try? snap.encoded() { try? data.write(to: backup, options: .atomic); backupURL = backup }
    }
}

struct ShareCardView: View {
    let trip: Trip
    let snapshot: TripSnapshot

    var body: some View {
        let f = Date.FormatStyle(timeZone: trip.timeZone).month(.abbreviated).day()
        let summary = ItineraryLogic.summary(trip.allItems)
        let titles = trip.allDays.sorted { $0.date < $1.date }.filter { !$0.title.isEmpty }
        HeroCard(
            eyebrow: "\(trip.startDate.formatted(f)) – \(trip.endDate.formatted(f)) · \(trip.kind.rawValue)",
            headline: trip.name,
            stats: [
                ("calendar", "\(TripLogic.dayCount(start: trip.localStart, end: trip.localEnd))", "days"),
                ("person.3.fill", "\(max(trip.allTravelers.count, 1))", "travelers"),
                ("checkmark.seal.fill", "\(summary.booked)/\(summary.total)", "booked"),
            ]
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(titles.prefix(5)) { day in
                    Label("\(Fmt.shortDate(day.date, in: trip.timeZone)) · \(day.title)", systemImage: "mappin.and.ellipse")
                        .lineLimit(1).font(.subheadline.weight(.medium))
                }
            }
        }
    }
}
