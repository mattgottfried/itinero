import SwiftUI
import SwiftData

/// Every reservation and confirmation number in one searchable place.
struct BookingsWalletView: View {
    let trip: Trip
    @State private var search = ""
    @State private var openItem: ItineraryItem?
    @State private var copyTick = 0

    private enum Kind: String, CaseIterable {
        case transport = "Flights & trains", stays = "Stays", other = "Other reservations"
    }
    private func kind(_ i: ItineraryItem) -> Kind {
        switch i.category { case .flight, .train: .transport; case .stay: .stays; default: .other }
    }

    private var items: [ItineraryItem] {
        trip.allItems
            .filter { $0.status == .booked || !$0.confirmation.isEmpty }
            .filter { SearchLogic.matches(search, in: [$0.title, $0.place, $0.confirmation, $0.details, $0.category.label]) }
            .sorted { ($0.startsAt ?? $0.day?.date ?? .distantFuture) < ($1.startsAt ?? $1.day?.date ?? .distantFuture) }
    }

    var body: some View {
        let all = items
        Group {
            if all.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No bookings yet" : "No matches", systemImage: "ticket")
                } description: {
                    Text(search.isEmpty ? "Booked items and anything with a confirmation number show up here." : "Try a different word or confirmation number.")
                }
            } else {
                List {
                    ForEach(Kind.allCases, id: \.self) { g in
                        let rows = all.filter { kind($0) == g }
                        if !rows.isEmpty {
                            Section(g.rawValue) {
                                ForEach(rows) { item in
                                    Button { openItem = item } label: { row(item) }
                                        .buttonStyle(.plain)
                                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                                        .contextMenu {
                                            if !item.confirmation.isEmpty {
                                                Button("Copy confirmation", systemImage: "doc.on.doc") {
                                                    UIPasteboard.general.string = item.confirmation
                                                    copyTick += 1
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Bookings")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search bookings and confirmations")
        .navigationDestination(item: $openItem) { ItemDetailView(item: $0, trip: trip) }
        .sensoryFeedback(.success, trigger: copyTick)
    }

    private func row(_ item: ItineraryItem) -> some View {
        let tz = ItemRow.zone(for: item, trip: trip)
        let when = item.startsAt.map { Fmt.shortDate($0, in: tz) + " · " + Fmt.time($0, in: tz) }
            ?? item.day.map { Fmt.shortDate($0.date, in: trip.timeZone) } ?? ""
        let tone = statusTone(for: item.status, daysUntil: item.startsAt.map { TripLogic.daysUntil($0) })
        return ListRowCard(
            tone: tone, tile: .symbol(item.category.symbol), title: item.title,
            subtitle: item.status.label, subtitleSymbol: item.status.symbol, subtitleTone: tone,
            accessibilityValue: [item.status.label, when, item.confirmation.isEmpty ? "no confirmation number" : "confirmation \(item.confirmation)"].joined(separator: ", "),
            accessibilityHint: "Open details"
        ) {
            VStack(alignment: .leading, spacing: 2) {
                if !when.isEmpty { Text(when) }
                if !item.confirmation.isEmpty {
                    Text(item.confirmation).font(.callout.monospaced().weight(.semibold)).foregroundStyle(.primary)
                }
            }
        }
    }
}
