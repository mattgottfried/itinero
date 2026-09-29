import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Keeps the things that live outside the app in step with the store: scheduled reminders and the widget feed.
/// Cheap to run (a few dozen items), so it just runs on launch, on foreground, and every 30 seconds.
@MainActor
enum AppSync {
    static let remindersKey = "remindersOn"
    static let meKey = "myTravelerName"
    private static let lastPlanKey = "lastReminderPlanHash"

    static func travelerID(named name: String, in trip: Trip) -> UUID? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return trip.allTravelers.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }?.id
    }

    static func run(trips: [Trip]) async {
        let defaults = UserDefaults.standard
        let me = defaults.string(forKey: meKey) ?? ""
        let active = trips.filter { TripLogic.phase(start: $0.localStart, end: $0.localEnd) != .past }
        writeWidget(active: active, me: me)
        if defaults.bool(forKey: remindersKey) { await scheduleReminders(active: active, me: me) }
    }

    // MARK: Widget

    private static func writeWidget(active: [Trip], me: String) {
        guard let trip = active.min(by: { $0.startDate < $1.startDate }) else { return }
        let mine = travelerID(named: me, in: trip)
        let now = Date.now
        let upcoming = trip.allItems
            .filter { ItineraryLogic.isVisible($0, for: mine) && !$0.isDone && $0.status != .cancelled }
            .compactMap { i -> NextUpSnapshot.Entry? in
                guard let s = i.startsAt, (i.endsAt ?? s) >= now else { return nil }
                return .init(id: i.id, title: i.title, place: i.place, startsAt: s,
                             timeZoneID: i.timeZoneID.isEmpty ? trip.timeZoneID : i.timeZoneID, symbol: i.category.symbol,
                             statusLabel: i.status.label, isBooked: i.status == .booked || i.status == .done)
            }
            .sorted { $0.startsAt < $1.startsAt }
        let snapshot = NextUpSnapshot(tripName: trip.name, tripStart: trip.localStart, tripEnd: trip.localEnd,
                                      generatedAt: now, entries: Array(upcoming.prefix(12)))
        if NextUpSnapshot.load()?.entries != snapshot.entries || NextUpSnapshot.load()?.tripName != snapshot.tripName {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Reminders

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func scheduleReminders(active: [Trip], me: String) async {
        var all: [PlannedReminder] = []
        for trip in active {
            let mine = travelerID(named: me, in: trip)
            let items = TripSnapshot(trip: trip).items.filter { ItineraryLogic.isVisible($0, for: mine) }
            all += ReminderPlanner.plan(items, now: .now) + ReminderPlanner.planAllAboard(items, now: .now)
        }
        let plan = Array(all.sorted { $0.fireDate < $1.fireDate }.prefix(ReminderPlanner.maxPending))
        let hash = plan.map { "\($0.id)|\($0.fireDate.timeIntervalSince1970)|\($0.body)" }.joined(separator: ";")
        guard UserDefaults.standard.string(forKey: lastPlanKey) != hash else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("tt-") })
        for r in plan {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, r.fireDate.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
        UserDefaults.standard.set(hash, forKey: lastPlanKey)
    }

    static func clearReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("tt-") })
        UserDefaults.standard.removeObject(forKey: lastPlanKey)
    }
}
