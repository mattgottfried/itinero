import Foundation

/// The slice of an itinerary item that ordering, filtering and summaries need.
/// Keeps this logic free of SwiftData so tests can use plain structs.
protocol Schedulable {
    var startsAt: Date? { get }
    var endsAt: Date? { get }
    var status: BookingStatus { get }
    var category: ItemCategory { get }
    var sortOrder: Int { get }
    var timeZoneID: String { get }
    var attendeeIDs: [UUID] { get }
    var isOptional: Bool { get }
}

struct BookingSummary: Equatable {
    var total = 0
    var booked = 0
    var needsBooking = 0
    /// Needs booking and happens inside `bookingUrgencyWindowDays`.
    var urgent = 0
}

enum ItineraryLogic {
    /// Minutes-into-the-day used to order a day's items. Stays with no time lead the day (check-in
    /// anchors it); other untimed items fall at noon so they don't jump to either end.
    /// Uses the item's own time zone (a 6:15 AM departure from Orlando sorts as 6:15, not as its Tokyo equivalent).
    static func sortMinutes(_ item: some Schedulable, calendar: Calendar) -> Int {
        if let start = item.startsAt {
            var cal = calendar
            if let zone = TimeZone(identifier: item.timeZoneID) { cal.timeZone = zone }
            let c = cal.dateComponents([.hour, .minute], from: start)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        return item.category == .stay ? -60 : 12 * 60
    }

    static func sorted<T: Schedulable>(_ items: [T], calendar: Calendar) -> [T] {
        items.sorted { a, b in
            let ma = sortMinutes(a, calendar: calendar), mb = sortMinutes(b, calendar: calendar)
            return ma != mb ? ma < mb : a.sortOrder < b.sortOrder
        }
    }

    /// Whose plan is this? `nil` traveler = everyone's view. An item with no attendees is for the group.
    static func isVisible(_ item: some Schedulable, for traveler: UUID?) -> Bool {
        guard let traveler else { return true }
        return item.attendeeIDs.isEmpty || item.attendeeIDs.contains(traveler)
    }

    static func summary<T: Schedulable>(_ items: [T], now: Date = .now, calendar: Calendar = .current) -> BookingSummary {
        var s = BookingSummary()
        for item in items where item.status != .cancelled && item.status != .idea {
            s.total += 1
            if item.status == .booked || item.status == .done { s.booked += 1 }
            if item.status == .needsBooking {
                s.needsBooking += 1
                if let start = item.startsAt,
                   TripLogic.daysUntil(start, now: now, calendar: calendar) <= bookingUrgencyWindowDays { s.urgent += 1 }
            }
        }
        return s
    }

    /// First timed, not-yet-done item at or after `now` (or still running).
    static func nextUp<T: Schedulable>(_ items: [T], now: Date) -> T? {
        items
            .filter { $0.status != .done && $0.status != .cancelled }
            .compactMap { item -> (T, Date)? in
                guard let start = item.startsAt else { return nil }
                let effectiveEnd = item.endsAt ?? start
                return effectiveEnd >= now ? (item, start) : nil
            }
            .min { $0.1 < $1.1 }?.0
    }
}
