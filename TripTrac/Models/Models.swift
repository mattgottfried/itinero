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
    /// Family sharing (Phase 4). Opt-in per trip; `cloudOwnerName` is "" for trips I own, else the owner's CloudKit name.
    var cloudSync = false
    var cloudOwnerName = ""
    var cruiseLine = ""
    var shipName = ""
    var cabin = ""
    var linkURLs: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.trip) var checklist: [ChecklistItem]? = []
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
    var allChecklist: [ChecklistItem] { checklist ?? [] }
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
    @Relationship(deleteRule: .nullify, inverse: \ChecklistItem.owner) var checklistItems: [ChecklistItem]? = []

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
    var isPaid = false
    var isDone = false
    var allAboardAt: Date?
    var linkURLs: [String] = []
    /// Cached from a place-name search; cleared whenever the place text changes.
    var latitude: Double?
    var longitude: Double?
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

@Model
final class ChecklistItem {
    var id = UUID()
    var title = ""
    var group = "To do"
    var isDone = false
    var sortOrder = 0
    var trip: Trip?
    var owner: Traveler?

    init(title: String, group: String = "To do") {
        self.title = title
        self.group = group
    }
}

extension ItineraryItem: Schedulable {
    var attendeeIDs: [UUID] { allAttendees.map(\.id) }
}

extension ItineraryItem: AllAboard {}

// MARK: - Snapshot bridge

extension TripSnapshot {
    init(trip: Trip) {
        self.init(id: trip.id, name: trip.name, destination: trip.destination, kindRaw: trip.kindRaw,
                  startDate: trip.startDate, endDate: trip.endDate, timeZoneID: trip.timeZoneID)
        notes = trip.notes; cruiseLine = trip.cruiseLine; shipName = trip.shipName; cabin = trip.cabin; linkURLs = trip.linkURLs
        travelers = trip.allTravelers.map { Traveler(id: $0.id, name: $0.name, team: $0.team) }
        days = trip.allDays.sorted { $0.date < $1.date }.map { Day(id: $0.id, date: $0.date, title: $0.title) }
        items = trip.allItems.sorted { $0.sortOrder < $1.sortOrder }.map { i in
            Item(id: i.id, title: i.title, place: i.place, address: i.address, categoryRaw: i.categoryRaw, statusRaw: i.statusRaw,
                 startsAt: i.startsAt, endsAt: i.endsAt, timeNote: i.timeNote, timeZoneID: i.timeZoneID,
                 confirmation: i.confirmation, details: i.details, isOptional: i.isOptional, isMustDo: i.isMustDo,
                 cost: i.cost, currency: i.currency, isPaid: i.isPaid, isDone: i.isDone, allAboardAt: i.allAboardAt,
                 linkURLs: i.linkURLs, latitude: i.latitude, longitude: i.longitude, sortOrder: i.sortOrder,
                 dayID: i.day?.id, attendeeIDs: i.allAttendees.map(\.id))
        }
        checklist = trip.allChecklist.sorted { $0.sortOrder < $1.sortOrder }.map {
            Check(id: $0.id, title: $0.title, group: $0.group, isDone: $0.isDone, sortOrder: $0.sortOrder, ownerID: $0.owner?.id)
        }
    }

    /// Inserts this snapshot as a new trip (same ids). Returns nil if a trip with this id already exists —
    /// restoring a backup never overwrites what's there.
    @discardableResult
    func insert(into context: ModelContext, existing: [Trip]) -> Trip? {
        guard !existing.contains(where: { $0.id == id }) else { return nil }
        let trip = Trip(name: name, destination: destination, startDate: startDate, endDate: endDate,
                        kind: TripKind(rawValue: kindRaw) ?? .land, notes: notes, timeZoneID: timeZoneID)
        trip.id = id
        trip.cruiseLine = cruiseLine; trip.shipName = shipName; trip.cabin = cabin; trip.linkURLs = linkURLs
        context.insert(trip)
        var people: [UUID: TripTrac.Traveler] = [:]
        for t in travelers {
            let m = TripTrac.Traveler(name: t.name, team: t.team); m.id = t.id; m.trip = trip
            context.insert(m); people[t.id] = m
        }
        var dayMap: [UUID: TripTrac.Day] = [:]
        for d in days {
            let m = TripTrac.Day(date: d.date, title: d.title); m.id = d.id; m.trip = trip
            context.insert(m); dayMap[d.id] = m
        }
        for i in items {
            let m = ItineraryItem(title: i.title, category: i.category, status: i.status)
            m.id = i.id; m.place = i.place; m.address = i.address; m.startsAt = i.startsAt; m.endsAt = i.endsAt
            m.timeNote = i.timeNote; m.timeZoneID = i.timeZoneID; m.confirmation = i.confirmation; m.details = i.details
            m.isOptional = i.isOptional; m.isMustDo = i.isMustDo; m.cost = i.cost; m.currency = i.currency
            m.isPaid = i.isPaid; m.isDone = i.isDone; m.allAboardAt = i.allAboardAt; m.linkURLs = i.linkURLs
            m.latitude = i.latitude; m.longitude = i.longitude; m.sortOrder = i.sortOrder
            m.trip = trip; m.day = i.dayID.flatMap { dayMap[$0] }
            m.attendees = i.attendeeIDs.compactMap { people[$0] }
            context.insert(m)
        }
        for c in checklist {
            let m = ChecklistItem(title: c.title, group: c.group)
            m.id = c.id; m.isDone = c.isDone; m.sortOrder = c.sortOrder; m.trip = trip; m.owner = c.ownerID.flatMap { people[$0] }
            context.insert(m)
        }
        return trip
    }
}
