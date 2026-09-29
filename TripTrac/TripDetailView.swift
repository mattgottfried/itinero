import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: Trip
    @State private var showingAddPlan = false

    private var sortedItems: [ItineraryItem] { trip.itinerary.sorted { $0.startsAt < $1.startsAt } }
    private var groupedItems: [(Date, [ItineraryItem])] {
        let groups = Dictionary(grouping: sortedItems) { Calendar.current.startOfDay(for: $0.startsAt) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
    private var daysCount: Int {
        max(1, (Calendar.current.dateComponents([.day], from: trip.startDate, to: trip.endDate).day ?? 0) + 1)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(trip.kind.rawValue, systemImage: trip.kind.symbol)
                        .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    Text(trip.destination).font(.title2.bold())
                    HStack(spacing: 18) {
                        Label("\(daysCount) days", systemImage: "calendar")
                        Label("\(trip.itinerary.count) plans", systemImage: "list.bullet")
                    }.font(.caption).foregroundStyle(.secondary)
                    if !trip.notes.isEmpty { Text(trip.notes).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            } header: { Text("TRIP OVERVIEW") }

            if groupedItems.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No plans yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add flights, stays, port days, meals, and activities to shape your itinerary.")
                    } actions: {
                        Button("Add to itinerary") { showingAddPlan = true }.buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedItems, id: \.0) { day, items in
                    Section {
                        ForEach(items) { item in
                            ItineraryRow(item: item) {
                                item.isCompleted.toggle()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button(item.isCompleted ? "Mark as planned" : "Mark complete", systemImage: item.isCompleted ? "circle" : "checkmark.circle") {
                                    item.isCompleted.toggle()
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { modelContext.delete(item) }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { items[$0] }.forEach(modelContext.delete)
                        }
                    } header: {
                        Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                            .font(.caption.weight(.bold)).tracking(0.6)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddPlan = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add itinerary item")
            }
        }
        .sheet(isPresented: $showingAddPlan) { ItineraryEditorView(trip: trip) }
    }
}

private struct ItineraryRow: View {
    @Bindable var item: ItineraryItem
    let onToggle: () -> Void

    private var symbol: String {
        switch item.category {
        case "Transport": "airplane"
        case "Stay": "bed.double.fill"
        case "Food": "fork.knife"
        case "Port day": "ferry"
        case "Activity": "sparkles"
        default: "mappin.and.ellipse"
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    Text(item.startsAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: symbol).font(.caption).foregroundStyle(item.isCompleted ? .green : .blue)
                }.frame(width: 55, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                        Spacer(minLength: 4)
                        if item.isCompleted { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    HStack(spacing: 6) {
                        Text(item.category)
                        if !item.place.isEmpty { Text("·"); Text(item.place).lineLimit(1) }
                    }.font(.caption).foregroundStyle(.secondary)
                    if !item.details.isEmpty { Text(item.details).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue("\(item.category), \(item.isCompleted ? "complete" : "planned") at \(item.startsAt.formatted(date: .omitted, time: .shortened))\(item.place.isEmpty ? "" : ", \(item.place)")")
        .accessibilityHint("Mark itinerary item complete")
    }
}

private struct ItineraryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    @State private var title = ""
    @State private var place = ""
    @State private var category = "Activity"
    @State private var startsAt = Date()
    @State private var details = ""

    private let categories = ["Activity", "Transport", "Stay", "Food", "Port day", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("PLAN") {
                    TextField("Title", text: $title)
                    TextField("Place", text: $place)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    DatePicker("Date and time", selection: $startsAt)
                }
                Section("DETAILS") {
                    TextField("Confirmation, address, or notes…", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add to Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let item = ItineraryItem(title: title.trimmingCharacters(in: .whitespaces), place: place, startsAt: startsAt, category: category, details: details)
        item.trip = trip
        modelContext.insert(item)
        dismiss()
    }
}
