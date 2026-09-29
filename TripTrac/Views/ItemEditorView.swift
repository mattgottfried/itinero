import SwiftUI
import SwiftData

/// Add or edit an itinerary item. Works on an `ItemDraft` and only writes to the model on save.
struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    let item: ItineraryItem?
    @State private var draft: ItemDraft
    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var saveTick = 0

    init(trip: Trip, item: ItineraryItem?) {
        self.trip = trip
        self.item = item
        var d = item.map { ItemDraft(item: $0) } ?? ItemDraft(dayDate: max(trip.startDate, min(trip.endDate, .now)))
        if item == nil { d.currency = UserDefaults.standard.string(forKey: "lastCurrency") ?? "USD" }
        _draft = State(initialValue: d)
        _hasStart = State(initialValue: d.startsAt != nil)
        _hasEnd = State(initialValue: d.endsAt != nil)
    }

    private var currencyChoices: [String] {
        var list = ["", "USD", "JPY", "EUR", "GBP", "CAD", "AUD", "MXN"]
        if !list.contains(draft.currency) { list.append(draft.currency) }
        return list
    }

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("WHAT") {
                    TextField("Title", text: $draft.title)
                    Picker("Category", selection: $draft.category) {
                        ForEach(ItemCategory.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Status", selection: $draft.status) {
                        ForEach(BookingStatus.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Toggle("Optional", isOn: $draft.isOptional)
                    Toggle("Must do", isOn: $draft.isMustDo)
                    Toggle("Done", isOn: $draft.isDone)
                }
                Section {
                    DatePicker("Day", selection: $draft.dayDate, in: trip.startDate...trip.endDate.addingTimeInterval(86_399), displayedComponents: .date)
                    Toggle("Starts at a set time", isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker("Starts", selection: Binding(get: { draft.startsAt ?? draft.dayDate }, set: { draft.startsAt = $0 }))
                    }
                    Toggle("Has an end time", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("Ends", selection: Binding(get: { draft.endsAt ?? draft.startsAt ?? draft.dayDate }, set: { draft.endsAt = $0 }))
                    }
                    if !hasStart { TextField("Rough time (e.g. Morning)", text: $draft.timeNote) }
                    if draft.category == .portDay || draft.category == .embark {
                        Toggle("All-aboard time", isOn: Binding(
                            get: { draft.allAboardAt != nil },
                            set: { draft.allAboardAt = $0 ? (draft.allAboardAt ?? draft.endsAt ?? draft.dayDate) : nil }
                        ).animation())
                        if draft.allAboardAt != nil {
                            DatePicker("All aboard", selection: Binding(get: { draft.allAboardAt ?? draft.dayDate }, set: { draft.allAboardAt = $0 }))
                        }
                    }
                } header: { Text("WHEN") } footer: {
                    Text("Times are in the trip's time zone (\(trip.timeZone.identifier.replacingOccurrences(of: "_", with: " "))).")
                }
                Section("WHERE") {
                    TextField("Place", text: $draft.place)
                    TextField("Address", text: $draft.address, axis: .vertical)
                }
                Section("WHO") {
                    if trip.allTravelers.isEmpty {
                        Text("Add travelers from the trip menu to say who's going.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(draft.attendeeIDs.isEmpty ? "Whole group" : "\(draft.attendeeIDs.count) of \(trip.allTravelers.count) travelers")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(trip.allTravelers) { t in
                            Toggle(isOn: Binding(
                                get: { draft.attendeeIDs.contains(t.id) },
                                set: { on in if on { draft.attendeeIDs.insert(t.id) } else { draft.attendeeIDs.remove(t.id) } }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(t.name)
                                    if !t.team.isEmpty { Text(t.team).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                Section("BOOKING") {
                    TextField("Confirmation number", text: $draft.confirmation).textInputAutocapitalization(.characters)
                    TextField("Notes", text: $draft.details, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    TextField("Cost", value: $draft.cost, format: .number).keyboardType(.decimalPad)
                    Picker("Currency", selection: $draft.currency) {
                        ForEach(currencyChoices, id: \.self) { Text($0.isEmpty ? "None" : $0).tag($0) }
                    }
                    Toggle("Paid", isOn: $draft.isPaid)
                } header: { Text("COST") } footer: { Text("Costs add up in the trip's Budget, split across the travelers on this item.") }
                Section("LINKS") { LinkListEditor(links: $draft.linkURLs) }
            }
            .environment(\.timeZone, trip.timeZone)
            .navigationTitle(item == nil ? "Add to Itinerary" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(item == nil ? "Add" : "Save") { save() }.disabled(!canSave) }
            }
            .sensoryFeedback(.success, trigger: saveTick)
        }
        .presentationDetents([.large])
    }

    private func save() {
        if !hasStart { draft.startsAt = nil }
        if !hasEnd { draft.endsAt = nil }
        if hasStart, draft.startsAt == nil { draft.startsAt = draft.dayDate }
        // A timed item always lives on the day its start time falls on.
        if let start = draft.startsAt { draft.dayDate = start }
        if let item {
            draft.apply(to: item, trip: trip, context: modelContext)
        } else {
            let new = ItineraryItem(title: draft.title)
            draft.sortOrder = (trip.allItems.map(\.sortOrder).max() ?? 0) + 10
            draft.apply(to: new, trip: trip, context: modelContext)
            modelContext.insert(new)
        }
        if draft.cost != nil, !draft.currency.isEmpty { UserDefaults.standard.set(draft.currency, forKey: "lastCurrency") }
        saveTick += 1
        dismiss()
    }
}
