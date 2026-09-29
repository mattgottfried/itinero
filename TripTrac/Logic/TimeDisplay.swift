import Foundation

enum TimeDisplay {
    /// The same instant in the traveler's own zone, or nil when it would read the same as the item's time.
    static func yourTime(for date: Date, itemZone: TimeZone, yourZone: TimeZone, locale: Locale = .current) -> String? {
        guard itemZone.secondsFromGMT(for: date) != yourZone.secondsFromGMT(for: date) else { return nil }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: yourZone))
        let abbr = zoneAbbreviation(yourZone, at: date)
        return "\(time) \(abbr)"
    }

    /// Friendly names for zones the system abbreviates as "GMT+9" in US English.
    private static let friendly: [String: String] = ["Asia/Tokyo": "JST", "Asia/Seoul": "KST"]

    static func zoneAbbreviation(_ zone: TimeZone, at date: Date) -> String {
        friendly[zone.identifier] ?? zone.abbreviation(for: date) ?? zone.identifier
    }
}

enum PortLogic {
    /// Ship's leaving: caution until 2 hours before all-aboard, alert inside 2 hours, bad once passed.
    static func allAboardTone(_ allAboard: Date, now: Date) -> StatusTone {
        let remaining = allAboard.timeIntervalSince(now)
        if remaining < 0 { return .bad }
        return remaining <= 2 * 3600 ? .alert : .caution
    }
}
