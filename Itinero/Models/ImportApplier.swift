import Foundation
import SwiftData

enum ImportApplier {
    /// A trip with the same name and start date is treated as already imported.
    static func existingTrip(matching parsed: ParsedTrip, in trips: [Trip]) -> Trip? {
        trips.first { $0.name == parsed.name && $0.startDate == parsed.start }
    }

    @discardableResult
    static func apply(_ parsed: ParsedTrip, into context: ModelContext) -> Trip {
        let trip = Trip(name: parsed.name, destination: parsed.destination, startDate: parsed.start,
                        endDate: parsed.end, kind: parsed.kind, timeZoneID: parsed.timeZoneID)
        context.insert(trip)

        var travelers: [String: Traveler] = [:]
        for t in parsed.travelers {
            let traveler = Traveler(name: t.name, team: t.team)
            traveler.trip = trip
            context.insert(traveler)
            travelers[t.name] = traveler
        }

        let cal = trip.calendar
        var days: [String: Day] = [:]
        func day(_ key: String) -> Day {
            if let d = days[key] { return d }
            let date = SiteImporter.date(key, calendar: cal) ?? parsed.start
            let d = Day(date: date, title: parsed.dayTitles[key] ?? "")
            d.trip = trip
            context.insert(d)
            days[key] = d
            return d
        }
        for key in parsed.dayTitles.keys.sorted() { _ = day(key) }

        for p in parsed.items {
            let item = ItineraryItem(title: p.title, category: p.category, status: p.status)
            item.startsAt = p.startsAt
            item.endsAt = p.endsAt
            item.timeNote = p.timeNote
            item.timeZoneID = p.timeZoneID
            item.place = p.place
            item.address = p.address
            item.confirmation = p.confirmation
            item.details = p.details
            item.isOptional = p.isOptional
            item.sortOrder = p.sortOrder
            item.trip = trip
            item.day = day(p.dayKey)
            item.attendees = p.attendeeNames.compactMap { travelers[$0] }
            context.insert(item)
        }
        return trip
    }
}
