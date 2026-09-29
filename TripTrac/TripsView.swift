import SwiftUI
import SwiftData

struct TripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var showingAddTrip = false

    private var upcomingTrips: [Trip] { trips.filter { $0.endDate >= .now }.sorted { $0.startDate < $1.startDate } }
    private var pastTrips: [Trip] { trips.filter { $0.endDate < .now }.sorted { $0.startDate > $1.startDate } }

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("Your next trip starts here", systemImage: "suitcase.rolling")
                    } description: {
                        Text("Plan a cruise or a land adventure, then build its itinerary day by day.")
                    } actions: {
                        Button("Plan a trip") { showingAddTrip = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let next = upcomingTrips.first {
                            Section {
                                NavigationLink(value: next) {
                                    NextTripCard(trip: next)
                                        .listRowInsets(EdgeInsets())
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            } header: { Text("UP NEXT").font(.caption.weight(.bold)).tracking(0.8) }
                        }
                        if !upcomingTrips.isEmpty {
                            Section("UPCOMING") {
                                ForEach(upcomingTrips.dropFirst(upcomingTrips.first == nil ? 0 : 1)) { trip in
                                    NavigationLink(value: trip) { TripRow(trip: trip) }
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                                .onDelete(perform: deleteUpcoming)
                            }
                        }
                        if !pastTrips.isEmpty {
                            Section("PAST TRIPS") {
                                ForEach(pastTrips) { trip in
                                    NavigationLink(value: trip) { TripRow(trip: trip) }
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                                .onDelete(perform: deletePast)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTrip = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Plan a trip")
                }
            }
            .sheet(isPresented: $showingAddTrip) { TripEditorView() }
        }
        .tint(AppTheme.standard.primaryColor)
    }

    private func deleteUpcoming(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(upcomingTrips.dropFirst(upcomingTrips.first == nil ? 0 : 1)[index]) }
    }
    private func deletePast(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(pastTrips[index]) }
    }
}

private struct NextTripCard: View {
    let trip: Trip
    var body: some View {
        let days = TripLogic.daysUntil(trip.startDate)
        HeroCard(
            eyebrow: "\(trip.kind.rawValue) · \(days > 0 ? "in \(days) days" : "underway")",
            headline: trip.name,
            stats: [
                ("calendar", "\(TripLogic.dayCount(start: trip.startDate, end: trip.endDate))", "days"),
                ("list.bullet", "\(trip.itinerary.count)", "plans"),
            ]
        ) {
            Label(trip.destination, systemImage: "mappin.and.ellipse")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trip.name)
        .accessibilityValue("\(trip.kind.rawValue), \(trip.destination), \(days > 0 ? "in \(days) days" : "underway")")
        .accessibilityHint("Open trip itinerary")
        .accessibilityAddTraits(.isButton)
    }
}

private struct TripRow: View {
    let trip: Trip
    var body: some View {
        let dates = "\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) – \(trip.endDate.formatted(date: .abbreviated, time: .omitted))"
        let past = TripLogic.phase(start: trip.startDate, end: trip.endDate) == .past
        ListRowCard(
            tone: past ? .neutral : .info, tile: .symbol(trip.kind.symbol),
            title: trip.name, subtitle: trip.destination, subtitleSymbol: "mappin.and.ellipse",
            dimmed: past,
            accessibilityValue: "\(trip.kind.rawValue), \(trip.destination), \(dates)",
            accessibilityHint: "Open trip itinerary"
        ) { Text(dates) }
    }
}
