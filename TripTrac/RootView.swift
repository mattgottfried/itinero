import SwiftUI
import SwiftData

/// The trips list plus the background upkeep (widget feed + reminders).
struct RootView: View {
    @Query private var trips: [Trip]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSync.remindersKey) private var remindersOn = false
    @AppStorage(AppSync.meKey) private var me = ""

    var body: some View {
        TripsView()
            .task(id: "\(scenePhase == .active)-\(remindersOn)-\(me)") {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await AppSync.run(trips: trips)
                    CloudSync.shared.reconcile()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
    }
}
