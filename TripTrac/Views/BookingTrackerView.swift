import SwiftUI
import SwiftData

/// Everything still marked "needs booking", soonest first, with one-swipe "mark booked".
struct BookingTrackerView: View {
    let trip: Trip
    @State private var openItem: ItineraryItem?
    @State private var marking: ItineraryItem?

    private var groups: [(bucket: BookingBucket, items: [ItineraryItem])] { BookingGroups.group(trip.allItems) }
    private var issueIDs: Set<UUID> { Set(ScheduleIssues.detect(trip.allItems, allTravelerIDs: Set(trip.allTravelers.map(\.id))).flatMap(\.itemIDs)) }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("Everything is booked", systemImage: "checkmark.seal.fill")
                } description: { Text("Nothing on this trip is marked “needs booking”.") }
            } else {
                List {
                    ForEach(groups, id: \.bucket) { group in
                        Section {
                            ForEach(group.items) { item in
                                Button { openItem = item } label: { ItemRow(item: item, trip: trip, hasIssue: issueIDs.contains(item.id), showDate: true) }
                                    .buttonStyle(.plain)
                                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                                    .swipeActions(edge: .trailing) {
                                        Button { marking = item } label: { Label("Booked", systemImage: "checkmark.seal.fill") }.tint(.green)
                                    }
                                    .contextMenu {
                                        Button("Mark booked…", systemImage: "checkmark.seal.fill") { marking = item }
                                    }
                            }
                        } header: {
                            Label("\(group.bucket.title) (\(group.items.count))", systemImage: group.bucket == .urgent ? "exclamationmark.circle.fill" : "clock")
                                .foregroundStyle(group.bucket.tone.color).font(.caption.weight(.bold))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Needs Booking")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openItem) { ItemDetailView(item: $0, trip: trip) }
        .sheet(item: $marking) { MarkBookedSheet(item: $0) }
    }
}

struct MarkBookedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: ItineraryItem
    @State private var confirmation = ""
    @State private var tick = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Confirmation number (optional)", text: $confirmation)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                } header: { Text(item.title) } footer: { Text("You can add the cost and links later from the item.") }
            }
            .navigationTitle("Mark Booked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Booked") {
                        item.status = .booked
                        let c = confirmation.trimmingCharacters(in: .whitespaces)
                        if !c.isEmpty { item.confirmation = c }
                        tick += 1
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.success, trigger: tick)
            .onAppear { confirmation = item.confirmation }
        }
        .presentationDetents([.medium])
    }
}
