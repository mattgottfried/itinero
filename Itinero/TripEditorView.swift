import SwiftUI
import SwiftData

struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var destination = ""
    @State private var kind: TripKind = .land
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(7 * 86_400)
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var notes = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !destination.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("THE TRIP") {
                    TextField("Trip name", text: $name)
                    TextField("Destination", text: $destination)
                    Picker("Trip type", selection: $kind) {
                        ForEach(TripKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    Picker("Time zone", selection: $timeZoneID) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                    }
                } header: { Text("DATES") } footer: {
                    Text("Times in the itinerary are shown in this time zone, wherever you are.")
                }
                Section("NOTES") {
                    TextField("Reservations, ideas, reminders…", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        // Keep the calendar day the user picked, anchored to the trip's own zone.
        func anchor(_ d: Date) -> Date {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
            return cal.date(from: c) ?? d
        }
        let trip = Trip(name: name.trimmingCharacters(in: .whitespaces),
                        destination: destination.trimmingCharacters(in: .whitespaces),
                        startDate: anchor(startDate), endDate: anchor(endDate),
                        kind: kind, notes: notes, timeZoneID: timeZoneID)
        modelContext.insert(trip)
        dismiss()
    }
}
