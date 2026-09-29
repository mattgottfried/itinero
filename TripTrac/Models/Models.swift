import Foundation
import SwiftData

enum TripKind: String, CaseIterable, Identifiable {
    case land = "Land trip"
    case cruise = "Cruise"
    var id: String { rawValue }
    var symbol: String { self == .cruise ? "ferry.fill" : "map.fill" }
}

// All stored properties have defaults and relationships are optional so the schema stays
// CloudKit-compatible (Phase 4 sharing). Every model has a stable `id` for record mapping.

@Model
final class Trip {
    var id = UUID()
    var name = ""
    var destination = ""
    var startDate = Date()
    var endDate = Date()
    var kindRaw = TripKind.land.rawValue
    var notes = ""
    var timeZoneID = TimeZone.current.identifier
    @Relationship(deleteRule: .cascade, inverse: \Day.trip) var days: [Day]? = []
    @Relationship(deleteRule: .cascade, inverse: \Traveler.trip) var travelers: [Traveler]? = []
    @Relationship(deleteRule: .cascade, inverse: \ItineraryItem.trip) var items: [ItineraryItem]? = []

    var kind: TripKind {
        get { TripKind(rawValue: kindRaw) ?? .land }
        set { kindRaw = newValue.rawValue }
    }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
    /// Start/end as calendar days in the device's own calendar (for countdowns and phase).
    var localStart: Date { TripLogic.reanchor(startDate, from: calendar) }
    var localEnd: Date { TripLogic.reanchor(endDate, from: calendar) }
    var allItems: [ItineraryItem] { items ?? [] }
    var allDays: [Day] { days ?? [] }
    var allTravelers: [Traveler] { (travelers ?? []).sorted { ($0.team, $0.name) < ($1.team, $1.name) } }

    init(name: String, destination: String, startDate: Date, endDate: Date,
         kind: TripKind = .land, notes: String = "", timeZoneID: String = TimeZone.current.identifier) {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.kindRaw = kind.rawValue
        self.notes = notes
        self.timeZoneID = timeZoneID
    }
}

@Model
final class Day {
    var id = UUID()
    var date = Date()          // start of day in the trip's time zone
    var title = ""
    var trip: Trip?
    @Relationship(deleteRule: .nullify, inverse: \ItineraryItem.day) var items: [ItineraryItem]? = []

    init(date: Date, title: String = "") {
        self.date = date
        self.title = title
    }
}

@Model
final class Traveler {
    var id = UUID()
    var name = ""
    var team = ""
    var trip: Trip?
    var itineraryItems: [ItineraryItem]? = []

    init(name: String, team: String = "") {
        self.name = name
        self.team = team
    }

    var initial: String { String(name.prefix(1)).uppercased() }
}

@Model
final class ItineraryItem {
    var id = UUID()
    var title = ""
    var place = ""
    var address = ""
    var categoryRaw = ItemCategory.activity.rawValue
    var statusRaw = BookingStatus.planned.rawValue
    var startsAt: Date?
    var endsAt: Date?
    var timeNote = ""
    var timeZoneID = ""
    var confirmation = ""
    var details = ""
    var isOptional = false
    var isMustDo = false
    var cost: Double?
    var currency = ""
    var sortOrder = 0
    var trip: Trip?
    var day: Day?
    /// Empty means the whole group.
    @Relationship(inverse: \Traveler.itineraryItems) var attendees: [Traveler]? = []

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var status: BookingStatus {
        get { BookingStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    var allAttendees: [Traveler] { attendees ?? [] }

    init(title: String, category: ItemCategory = .activity, status: BookingStatus = .planned) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.statusRaw = status.rawValue
    }
}

extension ItineraryItem: Schedulable {
    var attendeeIDs: [UUID] { allAttendees.map(\.id) }
}
