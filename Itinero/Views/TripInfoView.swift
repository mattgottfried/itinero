import SwiftUI
import SwiftData

struct TripInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip

    var body: some View {
        NavigationStack {
            Form {
                Section("TRIP") {
                    TextField("Name", text: $trip.name)
                    TextField("Destination", text: $trip.destination)
                    Picker("Type", selection: Binding(get: { trip.kind }, set: { trip.kind = $0 })) {
                        ForEach(TripKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    LabeledContent("Time zone", value: trip.timeZoneID.replacingOccurrences(of: "_", with: " "))
                }
                if trip.kind == .cruise {
                    Section("CRUISE") {
                        TextField("Cruise line", text: $trip.cruiseLine)
                        TextField("Ship", text: $trip.shipName)
                        TextField("Cabin / stateroom", text: $trip.cabin)
                    }
                }
                Section("NOTES") {
                    TextField("Anything worth remembering about this trip…", text: $trip.notes, axis: .vertical).lineLimit(4...12)
                }
                Section("LINKS") { LinkListEditor(links: $trip.linkURLs) }
            }
            .navigationTitle("Trip Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
