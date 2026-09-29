import Foundation

enum TripPhase: Equatable { case upcoming, inProgress, past }

/// Pure date logic, kept out of views so it can be unit tested.
enum TripLogic {
    static func phase(start: Date, end: Date, now: Date = .now, calendar: Calendar = .current) -> TripPhase {
        let today = calendar.startOfDay(for: now)
        if calendar.startOfDay(for: end) < today { return .past }
        if calendar.startOfDay(for: start) > today { return .upcoming }
        return .inProgress
    }

    /// Whole calendar days from `now` until `date` (negative if in the past).
    static func daysUntil(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Inclusive number of days a trip spans (Nov 13–27 → 15).
    static func dayCount(start: Date, end: Date, calendar: Calendar = .current) -> Int {
        max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) + 1)
    }
}
