import SwiftUI
import SwiftData

@main
struct ItineroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Trip.self, Day.self, Traveler.self, ItineraryItem.self, ChecklistItem.self)
        } catch {
            fatalError("Couldn't open the trip store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { CloudSync.shared.start(container: container) }
        }
        .modelContainer(container)
    }
}
