import SwiftUI
import SwiftData

@main
struct TripTracApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Trip.self, Day.self, Traveler.self, ItineraryItem.self, ChecklistItem.self])
    }
}
