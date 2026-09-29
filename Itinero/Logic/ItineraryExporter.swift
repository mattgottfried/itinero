import Foundation

enum ItineraryExporter {
    /// Plain-text itinerary, grouped by day, optionally for one traveler. Times are in each item's own zone.
    static func text(_ trip: TripSnapshot, travelerID: UUID? = nil, locale: Locale = .current) -> String {
        let names = Dictionary(uniqueKeysWithValues: trip.travelers.map { ($0.id, $0.name) })
        var lines: [String] = []
        let who = travelerID.flatMap { names[$0] }
        lines.append(trip.name + (who.map { " — \($0)'s plan" } ?? ""))
        lines.append(rangeText(trip, locale: locale))
        if !trip.destination.isEmpty { lines.append(trip.destination) }

        let byDay = Dictionary(grouping: trip.items.filter { ItineraryLogic.isVisible($0, for: travelerID) }) { $0.dayID }
        for day in trip.days.sorted(by: { $0.date < $1.date }) {
            let items = ItineraryLogic.sorted(byDay[day.id] ?? [], calendar: trip.calendar)
            guard !items.isEmpty else { continue }
            lines.append("")
            let header = day.date.formatted(Date.FormatStyle(locale: locale, timeZone: trip.timeZone).weekday(.wide).month(.abbreviated).day())
            lines.append(day.title.isEmpty ? header : "\(header) — \(day.title)")
            for item in items {
                lines.append(itemLine(item, trip: trip, names: names, showWho: travelerID == nil, locale: locale))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func rangeText(_ trip: TripSnapshot, locale: Locale) -> String {
        let f = Date.FormatStyle(locale: locale, timeZone: trip.timeZone).month(.abbreviated).day().year()
        return "\(trip.startDate.formatted(f)) – \(trip.endDate.formatted(f))"
    }

    private static func itemLine(_ item: TripSnapshot.Item, trip: TripSnapshot, names: [UUID: String], showWho: Bool, locale: Locale) -> String {
        let zone = TimeZone(identifier: item.timeZoneID) ?? trip.timeZone
        var parts: [String] = []
        if let s = item.startsAt {
            var t = s.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone))
            if let e = item.endsAt, e > s { t += "–" + e.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone)) }
            parts.append(t)
        } else if !item.timeNote.isEmpty { parts.append(item.timeNote) }
        parts.append(item.title)
        var line = "• " + parts.joined(separator: " ")
        if !item.place.isEmpty { line += " @ " + item.place }
        var tags: [String] = []
        if item.isDone { tags.append("done") } else if item.status != .planned { tags.append(item.status.label.lowercased()) }
        if item.isOptional { tags.append("optional") }
        if !item.confirmation.isEmpty { tags.append("conf \(item.confirmation)") }
        if showWho, !item.attendeeIDs.isEmpty { tags.append(item.attendeeIDs.compactMap { names[$0] }.sorted().joined(separator: ", ")) }
        if !tags.isEmpty { line += " (" + tags.joined(separator: "; ") + ")" }
        return line
    }
}

/// iCalendar (.ics) export so the plan can go in a family calendar.
enum ICSExporter {
    static func make(_ trip: TripSnapshot, travelerID: UUID? = nil, now: Date = .now) -> String {
        let names = Dictionary(uniqueKeysWithValues: trip.travelers.map { ($0.id, $0.name) })
        let dayByID = Dictionary(uniqueKeysWithValues: trip.days.map { ($0.id, $0) })
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//\(AppName.display)//EN", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:" + escape(trip.name)]
        for item in trip.items where ItineraryLogic.isVisible(item, for: travelerID) && item.status != .cancelled {
            var event = ["BEGIN:VEVENT", "UID:\(item.id.uuidString)@itinero", "DTSTAMP:" + utc(now)]
            if item.category == .stay {
                guard let day = item.dayID.flatMap({ dayByID[$0] }) else { continue }
                event.append("DTSTART;VALUE=DATE:" + dateOnly(day.date, trip.calendar))
                if let out = item.endsAt { event.append("DTEND;VALUE=DATE:" + dateOnly(out, trip.calendar)) }
            } else if let s = item.startsAt {
                event.append("DTSTART:" + utc(s))
                event.append("DTEND:" + utc(max(item.endsAt ?? s.addingTimeInterval(3600), s)))
            } else if let day = item.dayID.flatMap({ dayByID[$0] }) {
                let next = trip.calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
                event.append("DTSTART;VALUE=DATE:" + dateOnly(day.date, trip.calendar))
                event.append("DTEND;VALUE=DATE:" + dateOnly(next, trip.calendar))
            } else { continue }
            event.append("SUMMARY:" + escape(item.title))
            let loc = [item.place, item.address].filter { !$0.isEmpty }.joined(separator: ", ")
            if !loc.isEmpty { event.append("LOCATION:" + escape(loc)) }
            var desc: [String] = []
            if !item.confirmation.isEmpty { desc.append("Confirmation: \(item.confirmation)") }
            if item.status == .needsBooking { desc.append("NOT BOOKED YET") }
            if !item.attendeeIDs.isEmpty { desc.append("Who: " + item.attendeeIDs.compactMap { names[$0] }.sorted().joined(separator: ", ")) }
            if !item.details.isEmpty { desc.append(item.details) }
            if !desc.isEmpty { event.append("DESCRIPTION:" + escape(desc.joined(separator: "\n"))) }
            event.append("END:VEVENT")
            lines += event
        }
        lines.append("END:VCALENDAR")
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func utc(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian)
        var cal = c; cal.timeZone = TimeZone(identifier: "UTC")!
        let p = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", p.year!, p.month!, p.day!, p.hour!, p.minute!, p.second!)
    }

    static func dateOnly(_ d: Date, _ cal: Calendar) -> String {
        let p = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", p.year!, p.month!, p.day!)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// RFC 5545: lines are at most 75 octets; continuation lines start with a space.
    static func fold(_ line: String) -> [String] {
        var out: [String] = [], current = "", bytes = 0
        for ch in line {
            let n = String(ch).utf8.count
            if bytes + n > (out.isEmpty ? 75 : 74) {
                out.append(current); current = ""; bytes = 0
            }
            current.append(ch); bytes += n
        }
        out.append(current)
        return out.enumerated().map { $0.offset == 0 ? $0.element : " " + $0.element }
    }
}
