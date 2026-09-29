import SwiftUI
import SwiftData

struct TravelersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    @State private var newName = ""
    @State private var newTeam = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(trip.allTravelers) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.body.weight(.semibold))
                            if !t.team.isEmpty { Text(t.team).font(.caption).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        let travelers = trip.allTravelers
                        offsets.map { travelers[$0] }.forEach(modelContext.delete)
                    }
                } header: { Text("TRAVELERS") } footer: {
                    Text("Items with nobody selected are for the whole group. Removing someone doesn't delete any plans.")
                }
                Section("ADD") {
                    TextField("Name", text: $newName)
                    TextField("Team (optional)", text: $newTeam)
                    Button("Add traveler", systemImage: "person.badge.plus") {
                        let t = Traveler(name: newName.trimmingCharacters(in: .whitespaces), team: newTeam.trimmingCharacters(in: .whitespaces))
                        t.trip = trip
                        modelContext.insert(t)
                        newName = ""; newTeam = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Travelers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
