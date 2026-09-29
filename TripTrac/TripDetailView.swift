import SwiftUI
import SwiftData

enum TripSection: Hashable {
    case needsBooking, bookings, checklist, budget, map, issues
}

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: Trip
    @State private var filterTraveler: UUID?
    @State private var editing: ItineraryItem?
    @State private var openItem: ItineraryItem?
    @State private var section: TripSection?
    @State private var showingAdd = false
    @State private var showingTravelers = false
    @State private var showingInfo = false
    @State private var showingShare = false
    @State private var search = ""
    @State private var undoDraft: ItemDraft?
    @State private var undoMessage = ""

    private var summary: BookingSummary { ItineraryLogic.summary(trip.allItems) }
    private var days: [Day] { trip.allDays.sorted { $0.date < $1.date } }
    private var issues: [ScheduleIssue] {
        ScheduleIssues.detect(trip.allItems, allTravelerIDs: Set(trip.allTravelers.map(\.id)))
    }
    private var phase: TripPhase { TripLogic.phase(start: trip.localStart, end: trip.localEnd) }

    private func visibleItems(_ day: Day) -> [ItineraryItem] {
        let items = (day.items ?? []).filter { ItineraryLogic.isVisible($0, for: filterTraveler) }
        return ItineraryLogic.sorted(items, calendar: trip.calendar)
    }

    private var searchResults: [ItineraryItem] {
        trip.allItems
            .filter { item in
                SearchLogic.matches(search, in: [item.title, item.place, item.address, item.confirmation, item.details,
                                                 item.category.label, item.status.label,
                                                 item.allAttendees.map(\.name).joined(separator: " ")])
            }
            .sorted { a, b in
                let da = a.day?.date ?? .distantFuture, db = b.day?.date ?? .distantFuture
                if da != db { return da < db }
                return ItineraryLogic.sortMinutes(a, calendar: trip.calendar) < ItineraryLogic.sortMinutes(b, calendar: trip.calendar)
            }
    }

    var body: some View {
        let issueIDs = Set(issues.flatMap(\.itemIDs))
        List {
            if search.isEmpty {
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
                            ForEach(items) { item in row(item, hasIssue: issueIDs.contains(item.id), showDate: false) }
                        } header: { dayHeader(day, items: items) }
                    }
                }
            } else {
                Section("\(searchResults.count) RESULT\(searchResults.count == 1 ? "" : "S")") {
                    ForEach(searchResults) { item in row(item, hasIssue: issueIDs.contains(item.id), showDate: true) }
                }
                if searchResults.isEmpty {
                    ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Plans, places, confirmations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add to itinerary", systemImage: "plus") { showingAdd = true }
                    Button("Travelers", systemImage: "person.2") { showingTravelers = true }
                    Button("Trip info & notes", systemImage: "info.circle") { showingInfo = true }
                    Button("Share or back up…", systemImage: "square.and.arrow.up") { showingShare = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Trip actions")
            }
        }
        .sheet(isPresented: $showingAdd) { ItemEditorView(trip: trip, item: nil) }
        .sheet(item: $editing) { ItemEditorView(trip: trip, item: $0) }
        .sheet(isPresented: $showingTravelers) { TravelersView(trip: trip) }
        .sheet(isPresented: $showingInfo) { TripInfoView(trip: trip) }
        .sheet(isPresented: $showingShare) { ShareTripView(trip: trip) }
        .navigationDestination(item: $openItem) { ItemDetailView(item: $0, trip: trip) }
        .navigationDestination(item: $section) { destination(for: $0) }
        .overlay(alignment: .bottom) {
            if undoDraft != nil { UndoToast(message: undoMessage) { undo() }.padding(.bottom, 12) }
        }
        .animation(.easeInOut, value: undoDraft != nil)
    }

    @ViewBuilder private func destination(for section: TripSection) -> some View {
        switch section {
        case .needsBooking: BookingTrackerView(trip: trip)
        case .bookings: BookingsWalletView(trip: trip)
        case .checklist: ChecklistView(trip: trip)
        case .budget: BudgetView(trip: trip)
        case .map: DayMapView(trip: trip)
        case .issues: IssuesView(trip: trip)
        }
    }

    private func row(_ item: ItineraryItem, hasIssue: Bool, showDate: Bool) -> some View {
        Button { openItem = item } label: { ItemRow(item: item, trip: trip, hasIssue: hasIssue, showDate: showDate) }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            .swipeActions(edge: .leading) {
                Button { item.isDone.toggle() } label: {
                    Label(item.isDone ? "Not done" : "Done", systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark")
                }.tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") }
            }
            .contextMenu {
                Button(item.isDone ? "Mark not done" : "Mark done", systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark") { item.isDone.toggle() }
                ForEach([BookingStatus.booked, .needsBooking, .planned], id: \.self) { status in
                    Button(status.label, systemImage: status.symbol) { item.status = status }
                }
                Button("Edit", systemImage: "pencil") { editing = item }
                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
            }
    }

    // MARK: Header + hub

    private var header: some View {
        VStack(spacing: 12) {
            let days = TripLogic.daysUntil(trip.localStart)
            HeroCard(
                eyebrow: "\(trip.kind.rawValue) · \(phase == .upcoming ? "in \(days) days" : phase == .inProgress ? "underway" : "completed")",
                headline: trip.destination,
                stats: [
                    ("calendar", "\(TripLogic.dayCount(start: trip.localStart, end: trip.localEnd))", "days"),
                    ("checkmark.seal.fill", "\(summary.booked)/\(summary.total)", "booked"),
                    ("exclamationmark.circle", "\(summary.urgent)", "urgent"),
                ]
            ) {
                if trip.kind == .cruise, !(trip.shipName + trip.cabin).isEmpty {
                    Label([trip.shipName, trip.cabin.isEmpty ? "" : "Cabin \(trip.cabin)"].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "ferry.fill")
                }
            }
            if phase == .inProgress { todayCard }
            hub
            if !trip.allTravelers.isEmpty { travelerFilter }
        }
    }

    private var hub: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        let checklistDone = trip.allChecklist.filter(\.isDone).count
        let totals = BudgetLogic.totals(trip.allItems, travelerIDs: trip.allTravelers.map(\.id))
        let budgetValue: String = totals.first.map {
            BudgetLogic.format($0.planned, currency: $0.currency) + (totals.count > 1 ? " +\(totals.count - 1)" : "")
        } ?? "—"
        let bookingCount = trip.allItems.filter { !$0.confirmation.isEmpty }.count
        return LazyVGrid(columns: cols, spacing: 10) {
            HubTile(title: "To book", value: "\(summary.needsBooking)", systemImage: "exclamationmark.circle",
                    tone: summary.urgent > 0 ? .alert : summary.needsBooking > 0 ? .caution : .good) { section = .needsBooking }
            HubTile(title: "Bookings", value: "\(bookingCount)", systemImage: "ticket", tone: .good) { section = .bookings }
            HubTile(title: "Checklist", value: trip.allChecklist.isEmpty ? "—" : "\(checklistDone)/\(trip.allChecklist.count)",
                    systemImage: "checklist", tone: .info) { section = .checklist }
            HubTile(title: "Budget", value: budgetValue, systemImage: "creditcard", tone: .money) { section = .budget }
            HubTile(title: "Day map", value: "Map", systemImage: "map", tone: .info) { section = .map }
            HubTile(title: "Issues", value: "\(issues.count)", systemImage: "exclamationmark.triangle",
                    tone: issues.isEmpty ? .good : .caution) { section = .issues }
        }
    }

    private var todayCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let today = trip.calendar.startOfDay(for: now)
            let todays = (days.first { $0.date == today }.map(visibleItems)) ?? []
            let visibleAll = days.flatMap(visibleItems)
            let current = todays.first { ItineraryLogic.runState($0, now: now) == .happeningNow && !$0.isDone }
            let next = ItineraryLogic.nextUp(visibleAll.filter { $0.id != current?.id }, now: now)
            let progress = ItineraryLogic.progress(todays)
            SectionCard(title: "Today", systemImage: "sun.max.fill", tone: .star) {
                if let current {
                    Button { openItem = current } label: {
                        Label("Now: \(current.title)", systemImage: "play.circle.fill").font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                }
                if let next, let start = next.startsAt {
                    Button { openItem = next } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next: \(next.title)").font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                            HStack(spacing: 4) {
                                Text(start, style: .relative)
                                if !next.place.isEmpty { Text("· \(next.place)").lineLimit(1) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                } else if current == nil {
                    Text("Nothing else scheduled").font(.subheadline).foregroundStyle(.secondary)
                }
                if progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                    Text("\(progress.done) of \(progress.total) done today").font(.caption).foregroundStyle(.secondary)
                }
            }
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

    private func dayHeader(_ day: Day, items: [ItineraryItem]) -> some View {
        let p = ItineraryLogic.progress(items)
        return VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(Fmt.dayHeader(day.date, in: trip.timeZone)).font(.caption.weight(.bold)).tracking(0.6)
                if p.total > 0 && p.done > 0 {
                    Text("· \(p.done)/\(p.total) done").font(.caption2.weight(.semibold)).foregroundStyle(StatusTone.good.color)
                }
            }
            if !day.title.isEmpty { Text(day.title).font(.subheadline.weight(.semibold)).textCase(nil).foregroundStyle(.primary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
