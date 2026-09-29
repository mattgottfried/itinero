import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: Trip
    @State private var filterTraveler: UUID?
    @State private var editing: ItineraryItem?
    @State private var showingAdd = false
    @State private var showingTravelers = false
    @State private var undoDraft: ItemDraft?
    @State private var undoMessage = ""

    private var summary: BookingSummary { ItineraryLogic.summary(trip.allItems) }
    private var days: [Day] { trip.allDays.sorted { $0.date < $1.date } }

    private func visibleItems(_ day: Day) -> [ItineraryItem] {
        let items = (day.items ?? []).filter { ItineraryLogic.isVisible($0, for: filterTraveler) }
        return ItineraryLogic.sorted(items, calendar: trip.calendar)
    }

    var body: some View {
        List {
            Section { header.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)) }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)

            if trip.allItems.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No plans yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add flights, stays, meals and activities to build your itinerary.")
                    } actions: {
                        Button("Add to itinerary") { showingAdd = true }.buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(days) { day in
                let items = visibleItems(day)
                if !items.isEmpty || filterTraveler == nil {
                    Section {
                        ForEach(items) { item in
                            ItemRow(item: item, trip: trip)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = item }
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") }
                                }
                                .contextMenu { contextMenu(for: item) }
                        }
                    } header: { dayHeader(day) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add to itinerary", systemImage: "plus") { showingAdd = true }
                    Button("Travelers", systemImage: "person.2") { showingTravelers = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Trip actions")
            }
        }
        .sheet(isPresented: $showingAdd) { ItemEditorView(trip: trip, item: nil) }
        .sheet(item: $editing) { ItemEditorView(trip: trip, item: $0) }
        .sheet(isPresented: $showingTravelers) { TravelersView(trip: trip) }
        .overlay(alignment: .bottom) {
            if undoDraft != nil {
                UndoToast(message: undoMessage) { undo() }
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut, value: undoDraft != nil)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            let days = TripLogic.daysUntil(trip.localStart)
            let phase = TripLogic.phase(start: trip.localStart, end: trip.localEnd)
            HeroCard(
                eyebrow: "\(trip.kind.rawValue) · \(phase == .upcoming ? "in \(days) days" : phase == .inProgress ? "underway" : "completed")",
                headline: trip.destination,
                stats: [
                    ("calendar", "\(TripLogic.dayCount(start: trip.localStart, end: trip.localEnd))", "days"),
                    ("checkmark.seal.fill", "\(summary.booked)/\(summary.total)", "booked"),
                    ("exclamationmark.circle", "\(summary.urgent)", "urgent"),
                ]
            )
            if !trip.allTravelers.isEmpty { travelerFilter }
        }
    }

    private var travelerFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Everyone", symbol: "person.3.fill", selected: filterTraveler == nil) { filterTraveler = nil }
                ForEach(trip.allTravelers) { t in
                    chip(title: t.name, symbol: "person.fill", selected: filterTraveler == t.id) { filterTraveler = t.id }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filterTraveler)
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.white : AppTheme.standard.primaryColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? AppTheme.standard.primaryColor : AppTheme.standard.primaryColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Everyone" ? "Show everyone's plans" : "Show \(title)'s plans")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayHeader(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Fmt.dayHeader(day.date, in: trip.timeZone)).font(.caption.weight(.bold)).tracking(0.6)
            if !day.title.isEmpty { Text(day.title).font(.subheadline.weight(.semibold)).textCase(nil).foregroundStyle(.primary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func contextMenu(for item: ItineraryItem) -> some View {
        ForEach([BookingStatus.booked, .needsBooking, .planned, .done], id: \.self) { status in
            Button(status.label, systemImage: status.symbol) { item.status = status }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
    }

    // MARK: Delete / undo

    private func delete(_ item: ItineraryItem) {
        undoDraft = ItemDraft(item: item)
        undoMessage = "Deleted “\(item.title)”"
        modelContext.delete(item)
        let token = undoDraft?.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undoDraft?.id == token { undoDraft = nil }
        }
    }

    private func undo() {
        guard let draft = undoDraft else { return }
        let item = ItineraryItem(title: draft.title)
        draft.apply(to: item, trip: trip, context: modelContext)
        modelContext.insert(item)
        undoDraft = nil
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: ItineraryItem
    let trip: Trip

    var body: some View {
        let tz = item.timeZoneID.isEmpty ? trip.timeZone : (TimeZone(identifier: item.timeZoneID) ?? trip.timeZone)
        let days = item.startsAt.map { TripLogic.daysUntil($0) }
        let tone = statusTone(for: item.status, daysUntil: days)
        let time = Fmt.timeText(start: item.startsAt, end: item.endsAt, note: item.timeNote, in: tz)
        let who = item.allAttendees.isEmpty ? "" : item.allAttendees.sorted { $0.name < $1.name }.map(\.name).joined(separator: ", ")
        let checkout = item.category == .stay ? item.endsAt.map { "Check-out \(Fmt.shortDate($0, in: tz))" } : nil

        ListRowCard(
            tone: tone, tile: .symbol(item.category.symbol),
            title: item.title,
            subtitle: item.status.label, subtitleSymbol: item.status.symbol, subtitleTone: tone,
            dimmed: item.status == .done || item.status == .cancelled,
            accessibilityValue: [item.category.label, item.status.label, time, item.place,
                                 who.isEmpty ? "whole group" : who, item.isOptional ? "optional" : ""]
                .filter { !$0.isEmpty }.joined(separator: ", "),
            accessibilityHint: "Edit this item"
        ) {
            VStack(alignment: .leading, spacing: 3) {
                let line = [time, checkout ?? "", item.place].filter { !$0.isEmpty }.joined(separator: " · ")
                if !line.isEmpty { Text(line).lineLimit(2) }
                HStack(spacing: 6) {
                    if item.isOptional { BadgePill(text: "Optional", systemImage: "questionmark.circle", tone: .neutral) }
                    if item.isMustDo { BadgePill(text: "Must do", systemImage: "star.fill", tone: .star) }
                    if !who.isEmpty { Label(who, systemImage: "person.2.fill").lineLimit(1) }
                    if !item.confirmation.isEmpty { Label(item.confirmation, systemImage: "number").lineLimit(1) }
                }
            }
        }
    }
}
