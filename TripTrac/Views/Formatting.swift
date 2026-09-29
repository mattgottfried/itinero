import Foundation

/// Display formatting that always respects the item's or trip's own time zone.
enum Fmt {
    static func time(_ date: Date, in tz: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz))
    }

    static func dayHeader(_ date: Date, in tz: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: tz).weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }

    static func shortDate(_ date: Date, in tz: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: tz).month(.abbreviated).day())
    }

    /// "9:00 AM – 11:00 AM", "Morning", or "" when nothing is known.
    static func timeText(start: Date?, end: Date?, note: String, in tz: TimeZone) -> String {
        guard let start else { return note }
        var text = time(start, in: tz)
        if let end, end > start { text += " – " + time(end, in: tz) }
        return text
    }
}
