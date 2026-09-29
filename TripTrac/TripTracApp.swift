import SwiftUI
import SwiftData

@main
struct TripTracApp: App {
    var body: some Scene {
        WindowGroup {
            TripsView()
        }
        .modelContainer(for: [Trip.self, ItineraryItem.self])
    }
}
