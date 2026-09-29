import Foundation

struct PlannedReminder: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app.
    static let maxPending = 60

    static func leadTime(for category: ItemCategory) -> TimeInterval {
        switch category {
        case .flight: 3 * 3600
        case .train: 45 * 60
        case .embark, .disembark, .portDay: 90 * 60
        default: 60 * 60
        }
    }

    static func plan<T: Schedulable>(_ items: [T], now: Date, locale: Locale = .current) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for item in items where item.status != .cancelled && !item.isDone {
            guard let start = item.startsAt else { continue }
            let zone = TimeZone(identifier: item.timeZoneID) ?? .current
            let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone))
            var body = "\(time) \(TimeDisplay.zoneAbbreviation(zone, at: start))"
            if !item.place.isEmpty { body += " · \(item.place)" }
            if item.status == .needsBooking { body += " · not booked yet!" }

            let fire = start.addingTimeInterval(-leadTime(for: item.category))
            if fire > now { out.append(PlannedReminder(id: "tt-\(item.id.uuidString)-lead", fireDate: fire, title: item.title, body: body)) }
        }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    /// The ship leaves at all-aboard, not at the item's start — remind 2 hours before that.
    static func planAllAboard<T: Schedulable & AllAboard>(_ items: [T], now: Date) -> [PlannedReminder] {
        items.compactMap { item in
            guard item.status != .cancelled, !item.isDone, let aboard = item.allAboardAt else { return nil }
            let fire = aboard.addingTimeInterval(-2 * 3600)
            guard fire > now else { return nil }
            return PlannedReminder(id: "tt-\(item.id.uuidString)-aboard", fireDate: fire,
                                   title: "All aboard in 2 hours", body: item.title)
        }
    }
}

protocol AllAboard { var allAboardAt: Date? { get } }
extension TripSnapshot.Item: AllAboard {}
