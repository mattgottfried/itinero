import SwiftUI
import SwiftData
import MapKit

/// One day's stops as numbered pins. Coordinates come from a place-name search on the device and are cached
/// on the item, so pins can be approximate — the list below always shows the text the pin came from.
struct DayMapView: View {
    let trip: Trip
    @State private var dayID: UUID?
    @State private var position: MapCameraPosition = .automatic
    @State private var finding = false
    @State private var openItem: ItineraryItem?

    private var days: [Day] { trip.allDays.sorted { $0.date < $1.date }.filter { !($0.items ?? []).isEmpty } }
    private var day: Day? { days.first { $0.id == dayID } ?? defaultDay }
    private var defaultDay: Day? {
        let today = trip.calendar.startOfDay(for: .now)
        return days.first { $0.date == today }
            ?? days.first { d in (d.items ?? []).contains { !$0.place.isEmpty } }
            ?? days.first
    }
    private var stops: [ItineraryItem] {
        guard let day else { return [] }
        return ItineraryLogic.sorted(day.items ?? [], calendar: trip.calendar).filter { $0.status != .cancelled }
    }
    private var pinned: [(number: Int, item: ItineraryItem, coordinate: CLLocationCoordinate2D)] {
        stops.enumerated().compactMap { index, item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return (number: index + 1, item: item, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                ForEach(pinned, id: \.item.id) { pin in
                    Annotation(pin.item.title, coordinate: pin.coordinate) {
                        Text("\(pin.number)").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(statusTone(for: pin.item.status, daysUntil: nil).color, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .accessibilityLabel("Stop \(pin.number), \(pin.item.title)")
                    }
                }
            }
            .frame(height: 300)
            .overlay(alignment: .topTrailing) {
                if finding { ProgressView().padding(8).background(.regularMaterial, in: Circle()).padding(8) }
            }
            List {
                Section {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, item in
                        Button { openItem = item } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(item.latitude == nil ? Color.gray : statusTone(for: item.status, daysUntil: nil).color, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(item.place.isEmpty ? "No place — not on the map" : item.place)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Open details")
                    }
                } header: { Text("STOPS") } footer: {
                    Text("Pins are found from place names and can be approximate, especially for vague places like “restaurant near hotel”.")
                }
            }
            .listStyle(.insetGrouped)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Day Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Day", selection: Binding(get: { day?.id }, set: { dayID = $0 })) {
                        ForEach(days) { d in
                            Text(Fmt.dayHeader(d.date, in: trip.timeZone).capitalized).tag(Optional(d.id))
                        }
                    }
                } label: { Label(day.map { Fmt.dayHeader($0.date, in: trip.timeZone).capitalized } ?? "Day", systemImage: "calendar") }
                    .accessibilityLabel("Choose day")
            }
        }
        .navigationDestination(item: $openItem) { ItemDetailView(item: $0, trip: trip) }
        .task(id: day?.id) { await locateStops() }
    }

    @MainActor private func locateStops() async {
        position = .automatic
        let todo = stops.filter { $0.latitude == nil && MapLinks.query(place: $0.place, address: $0.address) != nil }
        guard !todo.isEmpty else { return }
        finding = true
        defer { finding = false }
        for item in todo {
            if Task.isCancelled { return }
            guard var query = MapLinks.query(place: item.place, address: item.address) else { continue }
            if !trip.destination.isEmpty, !query.localizedCaseInsensitiveContains(trip.destination) { query += ", \(trip.destination)" }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let response = try? await MKLocalSearch(request: request).start(), let first = response.mapItems.first {
                item.latitude = first.placemark.coordinate.latitude
                item.longitude = first.placemark.coordinate.longitude
                position = .automatic
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
