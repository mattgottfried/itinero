import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: ItineraryItem
    let trip: Trip
    @State private var editing = false
    @State private var copyTick = 0
    @State private var copiedMessage: String?
    @State private var confirmDelete = false

    private var tz: TimeZone { ItemRow.zone(for: item, trip: trip) }
    private var issues: [ScheduleIssue] {
        ScheduleIssues.detect(trip.allItems, allTravelerIDs: Set(trip.allTravelers.map(\.id))).filter { $0.itemIDs.contains(item.id) }
    }
    private var mapQuery: String? { MapLinks.query(place: item.place, address: item.address) }
    private var previousStopQuery: String? {
        guard let day = item.day else { return nil }
        let sorted = ItineraryLogic.sorted(day.items ?? [], calendar: trip.calendar)
        guard let idx = sorted.firstIndex(where: { $0.id == item.id }) else { return nil }
        return sorted[..<idx].reversed().compactMap { MapLinks.query(place: $0.place, address: $0.address) }.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                whenCard
                if mapQuery != nil { whereCard }
                whoCard
                bookingCard
                if !item.linkURLs.isEmpty { linksCard }
                if !item.details.isEmpty {
                    SectionCard(title: "Notes", systemImage: "note.text", tone: .neutral) {
                        Text(item.details).font(.subheadline).textSelection(.enabled)
                    }
                }
                if !issues.isEmpty {
                    SectionCard(title: "Check schedule", systemImage: "exclamationmark.triangle.fill", tone: .caution) {
                        ForEach(issues) { Text($0.message).font(.subheadline) }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.category.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Item actions")
            }
        }
        .sheet(isPresented: $editing) { ItemEditorView(trip: trip, item: item) }
        .confirmationDialog("Delete “\(item.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete item", role: .destructive) { modelContext.delete(item); dismiss() }
        }
        .sensoryFeedback(.success, trigger: copyTick)
        .overlay(alignment: .bottom) {
            if let copiedMessage {
                Text(copiedMessage).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: copiedMessage)
    }

    // MARK: Cards

    private var headerCard: some View {
        let tone: StatusTone = item.isDone ? .good : statusTone(for: item.status, daysUntil: item.startsAt.map { TripLogic.daysUntil($0) })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusTile(tone: tone, content: .symbol(item.category.symbol), size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        BookingBadge(status: item.status, daysUntil: item.startsAt.map { TripLogic.daysUntil($0) })
                        if item.isOptional { BadgePill(text: "Optional", systemImage: "questionmark.circle", tone: .neutral) }
                        if item.isMustDo { BadgePill(text: "Must do", systemImage: "star.fill", tone: .star) }
                    }
                }
            }
            if let aboard = item.allAboardAt {
                BadgePill(text: "All aboard \(Fmt.time(aboard, in: tz))", systemImage: "ferry.fill",
                          tone: PortLogic.allAboardTone(aboard, now: .now), solid: true)
            }
            Button {
                item.isDone.toggle()
            } label: {
                Label(item.isDone ? "Done — tap to undo" : "Mark done", systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(item.isDone ? .green : AppTheme.standard.primaryColor)
            .sensoryFeedback(.success, trigger: item.isDone)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.standard.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private var whenCard: some View {
        SectionCard(title: "When", systemImage: "clock", tone: .info) {
            if let day = item.day {
                Text(day.date.formatted(Date.FormatStyle(timeZone: trip.timeZone).weekday(.wide).month(.wide).day()))
                    .font(.subheadline.weight(.semibold))
                if !day.title.isEmpty { Text(day.title).font(.caption).foregroundStyle(.secondary) }
            }
            let time = Fmt.timeText(start: item.startsAt, end: item.endsAt, note: item.timeNote, in: tz)
            if item.category == .stay, let out = item.endsAt {
                Text("Check-out \(Fmt.shortDate(out, in: tz))").font(.subheadline)
            } else if !time.isEmpty {
                Text(time + (item.startsAt.map { " " + TimeDisplay.zoneAbbreviation(tz, at: $0) } ?? "")).font(.subheadline)
            } else {
                Text("Time not set").font(.subheadline).foregroundStyle(.secondary)
            }
            if let s = item.startsAt, let yours = TimeDisplay.yourTime(for: s, itemZone: tz, yourZone: .current) {
                Label("\(yours) your time", systemImage: "clock.arrow.2.circlepath").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var whereCard: some View {
        SectionCard(title: "Where", systemImage: "mappin.and.ellipse", tone: .info) {
            if !item.place.isEmpty { Text(item.place).font(.subheadline.weight(.semibold)) }
            if !item.address.isEmpty { Text(item.address).font(.subheadline).textSelection(.enabled) }
            if let q = mapQuery, let url = MapLinks.search(q) {
                Link(destination: url) { Label("Open in Maps", systemImage: "map") }
                if let prev = previousStopQuery, let dir = MapLinks.transitDirections(from: prev, to: q) {
                    Link(destination: dir) { Label("Transit directions from previous stop", systemImage: "tram.fill") }
                }
                Button { copy(q, message: "Address copied") } label: { Label("Copy address for a taxi", systemImage: "doc.on.doc") }
            }
        }
    }

    private var whoCard: some View {
        SectionCard(title: "Who", systemImage: "person.2.fill", tone: .info) {
            if item.allAttendees.isEmpty {
                Text(trip.allTravelers.isEmpty ? "Whole group" : "Whole group (\(trip.allTravelers.count))").font(.subheadline)
            } else {
                Text(item.allAttendees.map(\.name).sorted().joined(separator: ", ")).font(.subheadline)
            }
        }
    }

    private var bookingCard: some View {
        SectionCard(title: "Booking", systemImage: "ticket", tone: .info) {
            if item.confirmation.isEmpty {
                Text("No confirmation number yet").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(item.confirmation).font(.title3.monospaced().weight(.semibold)).textSelection(.enabled)
                    Spacer()
                    Button { copy(item.confirmation, message: "Confirmation copied") } label: { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("Copy confirmation number")
                }
            }
            if let cost = item.cost {
                HStack {
                    Label(BudgetLogic.format(cost, currency: item.currency), systemImage: "creditcard").foregroundStyle(StatusTone.money.color)
                    Spacer()
                    Toggle("Paid", isOn: $item.isPaid).labelsHidden()
                    Text(item.isPaid ? "Paid" : "Unpaid").font(.caption.weight(.semibold))
                }.font(.subheadline)
            }
            Menu {
                ForEach(BookingStatus.allCases) { s in Button(s.label, systemImage: s.symbol) { item.status = s } }
            } label: { Label("Change status", systemImage: "arrow.triangle.2.circlepath") }
        }
    }

    private var linksCard: some View {
        SectionCard(title: "Links", systemImage: "link", tone: .info) {
            ForEach(item.linkURLs, id: \.self) { l in
                if let url = URL(string: l) { Link(l.replacingOccurrences(of: "https://", with: ""), destination: url).lineLimit(1) }
            }
        }
    }

    private func copy(_ text: String, message: String) {
        UIPasteboard.general.string = text
        copyTick += 1
        copiedMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedMessage == message { copiedMessage = nil }
        }
    }
}
