import Foundation

enum BookingBucket: Int, CaseIterable {
    case urgent, later, undated

    var title: String {
        switch self {
        case .urgent: "Book soon — within \(bookingUrgencyWindowDays) days"
        case .later: "Later"
        case .undated: "No date yet"
        }
    }
    var tone: StatusTone { self == .urgent ? .alert : self == .later ? .caution : .neutral }
}

enum BookingGroups {
    /// Everything still marked "needs booking", bucketed by how soon it happens, soonest first.
    static func group<T: Schedulable>(_ items: [T], now: Date = .now, calendar: Calendar = .current) -> [(bucket: BookingBucket, items: [T])] {
        let open = items.filter { $0.status == .needsBooking }
        func bucket(_ i: T) -> BookingBucket {
            guard let s = i.startsAt else { return .undated }
            return TripLogic.daysUntil(s, now: now, calendar: calendar) <= bookingUrgencyWindowDays ? .urgent : .later
        }
        return BookingBucket.allCases.compactMap { b in
            let list = open.filter { bucket($0) == b }
                .sorted { ($0.startsAt ?? .distantFuture, $0.sortOrder) < ($1.startsAt ?? .distantFuture, $1.sortOrder) }
            return list.isEmpty ? nil : (bucket: b, items: list)
        }
    }
}
