import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var travelers: [Traveler]
    @AppStorage(AppSync.remindersKey) private var remindersOn = false
    @AppStorage(AppSync.meKey) private var me = ""
    @State private var denied = false

    private var names: [String] { Array(Set(travelers.map(\.name))).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("I'm traveling as", selection: $me) {
                        Text("Not set").tag("")
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                } header: { Text("YOU") } footer: {
                    Text("Reminders and the widget only show your own plans, and unassigned items are for everyone.")
                }
                Section {
                    Toggle("Reminders before things start", isOn: $remindersOn)
                        .onChange(of: remindersOn) { _, on in
                            Task {
                                if on {
                                    let ok = await AppSync.requestAuthorization()
                                    if !ok { remindersOn = false; denied = true }
                                } else { await AppSync.clearReminders() }
                            }
                        }
                } header: { Text("REMINDERS") } footer: {
                    Text("Flights 3 hours ahead, trains 45 minutes, most other things an hour, and 2 hours before all-aboard. Anything not booked yet says so.")
                }
                if denied {
                    Section { Text("Notifications are turned off for \(AppName.display). Enable them in Settings → Notifications.").font(.caption).foregroundStyle(StatusTone.caution.color) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
