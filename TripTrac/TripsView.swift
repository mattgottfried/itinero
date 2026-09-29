import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var showingAddTrip = false
    @State private var showingImporter = false
    @State private var report: ImportReport?
    @State private var importError: String?
    @State private var tripToDelete: Trip?

    private static let seedName = "japan-2026"
    private var seedURL: URL? { Bundle.main.url(forResource: Self.seedName, withExtension: "json") }

    private func phase(_ t: Trip) -> TripPhase { TripLogic.phase(start: t.localStart, end: t.localEnd) }
    private var current: [Trip] { trips.filter { phase($0) != .past }.sorted { $0.startDate < $1.startDate } }
    private var past: [Trip] { trips.filter { phase($0) == .past }.sorted { $0.startDate > $1.startDate } }

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty { emptyState } else { list }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trips")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Plan a trip", systemImage: "plus") { showingAddTrip = true }
                        Button("Import itinerary file…", systemImage: "square.and.arrow.down") { showingImporter = true }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add or import a trip")
                }
            }
            .sheet(isPresented: $showingAddTrip) { TripEditorView() }
            .sheet(item: $report) { ImportReportView(report: $0) }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    importFile(at: url)
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .confirmationDialog("Delete this trip and its itinerary?", isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete trip", role: .destructive) {
                    if let trip = tripToDelete { modelContext.delete(trip) }
                    tripToDelete = nil
                }
            } message: { Text("This can't be undone.") }
        }
        .tint(AppTheme.standard.primaryColor)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your next trip starts here", systemImage: "suitcase.rolling")
        } description: {
            Text("Plan a cruise or a land adventure, then build its itinerary day by day.")
        } actions: {
            if let seedURL {
                Button("Load Japan 2026 itinerary") { importFile(at: seedURL) }.buttonStyle(.borderedProminent)
                Button("Plan a trip") { showingAddTrip = true }
            } else {
                Button("Plan a trip") { showingAddTrip = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var list: some View {
        List {
            if let next = current.first {
                Section {
                    NextTripCard(trip: next)
                        .overlay { NavigationLink(value: next) { EmptyView() }.opacity(0) }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: { Text("UP NEXT").font(.caption.weight(.bold)).tracking(0.8) }
            }
            if current.count > 1 {
                Section("UPCOMING") { ForEach(current.dropFirst()) { row($0) } }
            }
            if !past.isEmpty {
                Section("PAST TRIPS") { ForEach(past) { row($0) } }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ trip: Trip) -> some View {
        NavigationLink(value: trip) { TripRow(trip: trip) }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .contextMenu {
                Button("Delete trip", systemImage: "trash", role: .destructive) { tripToDelete = trip }
            }
    }

    private func importFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let parsed = try SiteImporter.parse(data)
            if let existing = ImportApplier.existingTrip(matching: parsed, in: trips) {
                importError = "“\(existing.name)” is already in your trips, so nothing was imported."
                return
            }
            let trip = ImportApplier.apply(parsed, into: modelContext)
            report = ImportReport(tripName: trip.name, itemCount: parsed.items.count, warnings: parsed.warnings)
        } catch {
            importError = "The file isn't a TripTrac itinerary export. (\(error.localizedDescription))"
        }
    }
}

struct ImportReport: Identifiable {
    let id = UUID()
    let tripName: String
    let itemCount: Int
    let warnings: [ImportWarning]
}

private struct NextTripCard: View {
    let trip: Trip
    var body: some View {
        let days = TripLogic.daysUntil(trip.localStart)
        let when = days > 0 ? "in \(days) days" : "underway"
        let summary = ItineraryLogic.summary(trip.allItems)
        HeroCard(
            eyebrow: "\(trip.kind.rawValue) · \(when)",
            headline: trip.name,
            stats: [
                ("calendar", "\(TripLogic.dayCount(start: trip.localStart, end: trip.localEnd))", "days"),
                ("checkmark.seal.fill", "\(summary.booked)", "booked"),
                ("exclamationmark.circle", "\(summary.needsBooking)", "to book"),
            ]
        ) {
            Label(trip.destination, systemImage: "mappin.and.ellipse")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trip.name)
        .accessibilityValue("\(trip.kind.rawValue), \(trip.destination), \(when). \(summary.booked) booked, \(summary.needsBooking) still to book.")
        .accessibilityHint("Open trip itinerary")
        .accessibilityAddTraits(.isButton)
    }
}

private struct TripRow: View {
    let trip: Trip
    var body: some View {
        let tz = trip.timeZone
        let dates = "\(Fmt.shortDate(trip.startDate, in: tz)) – \(Fmt.shortDate(trip.endDate, in: tz))"
        let past = TripLogic.phase(start: trip.localStart, end: trip.localEnd) == .past
        ListRowCard(
            tone: past ? .neutral : .info, tile: .symbol(trip.kind.symbol),
            title: trip.name, subtitle: trip.destination, subtitleSymbol: "mappin.and.ellipse",
            dimmed: past,
            accessibilityValue: "\(trip.kind.rawValue), \(trip.destination), \(dates)",
            accessibilityHint: "Open trip itinerary"
        ) { Text(dates) }
    }
}
