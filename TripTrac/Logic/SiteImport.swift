import Foundation

/// Import of a trip from the JSON produced by scraping the family's itinerary web page
/// (format documented in docs/IMPORT_FORMAT.md). Pure: no SwiftData, no UI.
struct ImportWarning: Hashable, Identifiable {
    var item: String
    var message: String
    var id: String { item + "|" + message }
}

struct ParsedItem: Equatable {
    var dayKey: String              // "yyyy-MM-dd" in the trip's time zone
    var title: String
    var category: ItemCategory
    var status: BookingStatus
    var startsAt: Date?
    var endsAt: Date?
    var timeNote = ""
    var timeZoneID: String
    var place = ""
    var address = ""
    var confirmation = ""
    var details = ""
    /// Empty means "the whole group" (unspecified or "All 7").
    var attendeeNames: [String] = []
    var isOptional = false
    var sortOrder: Int
}

struct ParsedTrip {
    var name: String
    var destination: String
    var kind: TripKind
    var start: Date
    var end: Date
    var timeZoneID: String
    var travelers: [(name: String, team: String)]
    var dayTitles: [String: String]
    var items: [ParsedItem]
    var warnings: [ImportWarning]
}

enum SiteImporter {
    struct FileFormat: Decodable {
        struct TripInfo: Decodable { let name, destination, kind, start, end, timeZone: String }
        struct Traveler: Decodable { let name: String; let team: String? }
        struct Record: Decodable {
            let date, category, title: String
            let booked: Bool
            let meta: [String]
            let notes: String
        }
        let trip: TripInfo
        let travelers: [Traveler]
        let days: [String: String]
        let items: [Record]
    }

    /// Time zones for the airports we know about; everything else falls back to the trip's zone.
    static let airportZones: [String: String] = [
        "MCO": "America/New_York", "MSP": "America/Chicago", "LAX": "America/Los_Angeles",
        "HND": "Asia/Tokyo", "NRT": "Asia/Tokyo", "KIX": "Asia/Tokyo",
    ]

    static func parse(_ data: Data) throws -> ParsedTrip {
        parse(file: try JSONDecoder().decode(FileFormat.self, from: data))
    }

    static func parse(file: FileFormat) -> ParsedTrip {
        let zone = TimeZone(identifier: file.trip.timeZone) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let roster = file.travelers.map(\.name)
        var warnings: [ImportWarning] = []
        let year = Int(file.trip.start.prefix(4)) ?? 2026

        var items: [ParsedItem] = []
        for (index, rec) in file.items.enumerated() {
            let (item, w) = parseRecord(rec, index: index, roster: roster, year: year, tripZone: zone)
            items.append(item)
            warnings += w.map { ImportWarning(item: rec.title, message: $0) }
        }
        return ParsedTrip(
            name: file.trip.name, destination: file.trip.destination,
            kind: file.trip.kind == "cruise" ? .cruise : .land,
            start: date(file.trip.start, calendar: cal) ?? .now,
            end: date(file.trip.end, calendar: cal) ?? .now,
            timeZoneID: zone.identifier,
            travelers: file.travelers.map { (name: $0.name, team: $0.team ?? "") },
            dayTitles: file.days, items: items, warnings: warnings)
    }

    // MARK: - Record

    static func parseRecord(_ rec: FileFormat.Record, index: Int, roster: [String], year: Int,
                            tripZone: TimeZone) -> (ParsedItem, [String]) {
        var warnings: [String] = []
        let notes = parseNotes(rec.notes, roster: roster)
        var item = ParsedItem(dayKey: rec.date, title: rec.title, category: .other,
                              status: .planned, timeZoneID: tripZone.identifier, sortOrder: index)
        item.attendeeNames = notes.attendees
        item.isOptional = notes.isOptional
        var detailParts = notes.remainder
        var zone = tripZone
        var cal = Calendar(identifier: .gregorian)

        switch rec.category {
        case "flight":
            item.category = (rec.title + rec.meta.joined()).localizedCaseInsensitiveContains("shinkansen") ? .train : .flight
            var airline = "", route = "", when = ""
            for m in rec.meta {
                if m.hasPrefix("Conf:") { item.confirmation = String(m.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                else if m.contains("→") { route = m }
                else if matches(#"^[A-Z][a-z]{2} \d{1,2}, \d{1,2}:\d{2} [AP]M$"#, m) { when = m }
                else if airline.isEmpty { airline = m }
            }
            let ends = route.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
            if ends.count == 2 {
                item.place = ends[1] == "?" ? "" : ends[1]
                if ends[1] == "?" { warnings.append("Destination airport not set yet") }
                if let z = airportZones[ends[0]].flatMap(TimeZone.init(identifier:)) { zone = z }
            }
            cal.timeZone = zone
            item.timeZoneID = zone.identifier
            item.details = [airline, route].filter { !$0.isEmpty }.joined(separator: " · ")
            if !when.isEmpty { item.startsAt = parseMonthDayTime(when, year: year, calendar: cal) }
            else if item.category != .train { warnings.append("No departure time") }

        case "hotel":
            item.category = .stay
            cal.timeZone = tripZone
            var name = "", range = ""
            for m in rec.meta {
                if m.hasPrefix("Conf:") { item.confirmation = String(m.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                else if m.contains("→"), matches(#"^\w{3}, \w{3} \d{1,2} → \w{3}, \w{3} \d{1,2}$"#, m) { range = m }
                else if m.rangeOfCharacter(from: .decimalDigits) != nil, m.contains(",") || m.contains("-") { item.address = m }
                else if name.isEmpty { name = m }
            }
            item.place = name
            if !range.isEmpty {
                let parts = range.components(separatedBy: " → ")
                let inDate = parseWeekdayMonthDay(parts[0], year: year, calendar: cal)
                let outDate = parseWeekdayMonthDay(parts[1], year: year, calendar: cal)
                if let inDate, let outDate {
                    if outDate < inDate {
                        warnings.append("Check-out (\(parts[1])) is before check-in (\(parts[0])) — dates not imported")
                    } else {
                        item.endsAt = cal.date(bySettingHour: 11, minute: 0, second: 0, of: outDate)
                        if cal.startOfDay(for: inDate) != date(rec.date, calendar: cal) {
                            warnings.append("Check-in date (\(parts[0])) differs from the day it's listed on")
                        }
                    }
                }
            }

        default: // activity
            cal.timeZone = tripZone
            var clock: (Int, Int)?
            var timeText = ""
            for (i, m) in rec.meta.enumerated() {
                if i == 0, let c = parseClock(m) { clock = c; continue }
                if m.hasPrefix("Conf:") { item.confirmation = String(m.dropFirst(5)).trimmingCharacters(in: .whitespaces); continue }
                if looksLikeTimeText(m) { timeText = m; continue }
                let names = namesOnly(m, roster: roster)
                if !names.isEmpty { if item.attendeeNames.isEmpty { item.attendeeNames = names }; continue }
                if item.place.isEmpty { item.place = m }
            }
            let (main, note) = splitNote(timeText)
            if !note.isEmpty { detailParts.append(note) }
            let range = parseTimeRange(main)
            if let range {
                if let clock, clock.0 * 60 + clock.1 != range.start.0 * 60 + range.start.1 {
                    warnings.append(String(format: "Start time %02d:%02d disagrees with listed \"%@\" — using the listed time", clock.0, clock.1, main))
                }
                clock = range.start
            } else if !main.isEmpty {
                item.timeNote = main
            }
            if let clock { item.startsAt = dateTime(rec.date, hour: clock.0, minute: clock.1, calendar: cal) }
            if let end = range?.end { item.endsAt = dateTime(rec.date, hour: end.0, minute: end.1, calendar: cal) }
            if item.place.isEmpty { warnings.append("No place listed") }
            item.category = categoryFor(tag: notes.tag)
        }

        item.details = ([item.details] + detailParts).filter { !$0.isEmpty }.joined(separator: " — ")
        let lower = rec.title.lowercased()
        let isLogistics = lower.contains("check out") || lower.hasPrefix("arrive")
        let needs = notes.needsReservation || (rec.category != "activity" && !isLogistics)
        item.status = rec.booked ? .booked : (needs ? .needsBooking : .planned)
        return (item, warnings)
    }

    static func categoryFor(tag: String?) -> ItemCategory {
        switch tag?.lowercased() {
        case "meal": .meal
        case "day trip": .dayTrip
        case "disney": .themePark
        case "rest / free time": .rest
        default: .activity
        }
    }

    // MARK: - Notes ("Matt · Heather — [Activity] — needs booking/reservation")

    struct NotesInfo: Equatable {
        var attendees: [String] = []
        var isOptional = false
        var needsReservation = false
        var tag: String?
        var remainder: [String] = []
    }

    static func parseNotes(_ notes: String, roster: [String]) -> NotesInfo {
        var info = NotesInfo()
        let segments = notes.components(separatedBy: " — ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = segments.first else { return info }
        var rest = segments
        let tokens = first.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        let isWho = matches(#"^All \d+"#, first) || roster.contains { tokens[0].hasPrefixWord($0) }
        if isWho {
            rest.removeFirst()
            for token in tokens {
                var t = token
                var parens: [String] = []
                while let r = t.range(of: #"\s*\(([^)]*)\)"#, options: .regularExpression) {
                    parens.append(String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: " ()")))
                    t.removeSubrange(r)
                }
                for p in parens {
                    if p.lowercased().hasPrefix("optional") { info.isOptional = true }
                    else if !matches(#"^Team \d"#, p) { info.remainder.append(p) }
                }
                if matches(#"^All \d+"#, t) { continue }
                if let name = roster.first(where: { $0 == t }) { info.attendees.append(name) }
                else if let name = roster.first(where: { t.hasPrefixWord($0) }) {
                    info.attendees.append(name)
                    info.remainder.append(t)
                } else if !t.isEmpty { info.remainder.append(t) }
            }
        }
        for seg in rest {
            if let g = captures(#"^\[(.+)\]$"#, seg) { info.tag = g[0] }
            else if seg.lowercased() == "needs booking/reservation" { info.needsReservation = true }
            else { info.remainder.append(seg) }
        }
        return info
    }

    static func namesOnly(_ s: String, roster: [String]) -> [String] {
        let parts = s.replacingOccurrences(of: " - ", with: " · ").components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.allSatisfy({ roster.contains($0) }) ? parts : []
    }

    // MARK: - Time parsing

    static func parseClock(_ s: String) -> (Int, Int)? {
        guard let g = captures(#"^(\d{1,2}):(\d{2})$"#, s), let h = Int(g[0]), let m = Int(g[1]), h < 24, m < 60 else { return nil }
        return (h, m)
    }

    static func looksLikeTimeText(_ s: String) -> Bool {
        matches(#"^\d{1,2}(:\d{2})?\s*(am|pm)?\s*([–-]|\+|$|\s)"#, s) || matches(#"^(Morning|Afternoon|Evening|Night)"#, s)
    }

    static func splitNote(_ s: String) -> (String, String) {
        let parts = s.components(separatedBy: " — ")
        return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: " — "))
    }

    /// "4:30–6:30pm", "9:00–12:00pm", "7:00pm", "3:00pm+", "9:00pm–late", "6:30am depart".
    /// Returns nil for descriptive text like "Morning".
    static func parseTimeRange(_ s: String) -> (start: (Int, Int), end: (Int, Int)?)? {
        guard let g = captures(#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s*[–-]\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)?"#, s) else { return nil }
        guard let sh = Int(g[0]) else { return nil }
        let sm = Int(g[1]) ?? 0
        let sSuffix = g[2], eSuffix = g[5]
        var end: (Int, Int)?
        if let eh = Int(g[3]) {
            end = (to24(eh, eSuffix.isEmpty ? sSuffix : eSuffix), Int(g[4]) ?? 0)
        }
        var start = (to24(sh, sSuffix.isEmpty ? eSuffix : sSuffix), sm)
        // "9:00–12:00pm": 9 inherits pm → 21:00 which is after the end, so it must be am.
        if sSuffix.isEmpty, let end, start.0 * 60 + start.1 >= end.0 * 60 + end.1 {
            start = (to24(sh, "am"), sm)
        }
        if sSuffix.isEmpty && eSuffix.isEmpty && !s.contains(":") { return nil }
        return (start, end)
    }

    private static func to24(_ h: Int, _ suffix: String) -> Int {
        switch suffix {
        case "pm": return h % 12 + 12
        case "am": return h % 12
        default: return h
        }
    }

    static func parseMonthDayTime(_ s: String, year: Int, calendar: Calendar) -> Date? {
        guard let g = captures(#"^([A-Z][a-z]{2}) (\d{1,2}), (\d{1,2}):(\d{2}) ([AP]M)$"#, s),
              let month = monthNumber(g[0]), let day = Int(g[1]), let h = Int(g[2]), let m = Int(g[3]) else { return nil }
        let hour = to24(h, g[4].lowercased())
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: m))
    }

    static func parseWeekdayMonthDay(_ s: String, year: Int, calendar: Calendar) -> Date? {
        guard let g = captures(#"^\w{3}, (\w{3}) (\d{1,2})$"#, s), let month = monthNumber(g[0]), let day = Int(g[1]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func monthNumber(_ abbr: String) -> Int? {
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].firstIndex(of: abbr).map { $0 + 1 }
    }

    static func date(_ ymd: String, calendar: Calendar) -> Date? {
        dateTime(ymd, hour: 0, minute: 0, calendar: calendar)
    }

    static func dateTime(_ ymd: String, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour, minute: minute))
    }

    // MARK: - Regex helpers

    static func captures(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<max(m.numberOfRanges, 1)).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }

    static func matches(_ pattern: String, _ s: String) -> Bool { captures(pattern, s) != nil }
}

private extension String {
    /// True when the string equals `word` or starts with it followed by a space.
    func hasPrefixWord(_ word: String) -> Bool { self == word || hasPrefix(word + " ") }
}
