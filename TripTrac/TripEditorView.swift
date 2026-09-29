import SwiftUI
import SwiftData

struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var destination = ""
    @State private var kind: TripKind = .land
    @State private var startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1)) ?? .now
    @State private var endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14)) ?? .now
    @State private var notes = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !destination.trimmingCharacters(in: .whitespaces).isEmpty }

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
                Section("DATES") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section("NOTES") {
                    TextField("Reservations, ideas, reminders…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                if name.isEmpty && destination.isEmpty {
                    Section {
                        Button {
                            name = "Japan family trip"
                            destination = "Japan"
                            kind = .land
                        } label: {
                            Label("Start planning Japan", systemImage: "sparkles")
                        }
                    } footer: {
                        Text("Dates are prefilled for a two week November trip. Adjust them to match your plans.")
                    }
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let trip = Trip(name: name.trimmingCharacters(in: .whitespaces), destination: destination.trimmingCharacters(in: .whitespaces), startDate: startDate, endDate: endDate, kind: kind, notes: notes)
        modelContext.insert(trip)
        dismiss()
    }
}
