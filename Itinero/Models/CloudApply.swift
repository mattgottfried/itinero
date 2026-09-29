import Foundation
import SwiftData

/// Applies records that arrived from CloudKit to the local store. Upsert by id; never deletes anything that
/// wasn't explicitly deleted remotely.
enum CloudApply {
    static func trip(id: UUID, in context: ModelContext) -> Trip? {
        var d = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Creates the trip if we've never seen it (a share just arrived), otherwise updates its header.
    @discardableResult
    static func applyHeader(_ h: TripHeader, owner: String, context: ModelContext) -> Trip {
        let trip = trip(id: h.id, in: context) ?? {
            let t = Trip(name: h.name, destination: h.destination, startDate: h.startDate, endDate: h.endDate)
            t.id = h.id
            t.cloudSync = true
            t.cloudOwnerName = owner
            context.insert(t)
            return t
        }()
        trip.name = h.name; trip.destination = h.destination; trip.kindRaw = h.kindRaw
        trip.startDate = h.startDate; trip.endDate = h.endDate; trip.timeZoneID = h.timeZoneID
        trip.notes = h.notes; trip.cruiseLine = h.cruiseLine; trip.shipName = h.shipName; trip.cabin = h.cabin
        trip.linkURLs = h.linkURLs
        return trip
    }

    static func upsert(_ t: TripSnapshot.Traveler, into trip: Trip, context: ModelContext) {
        let m = trip.allTravelers.first { $0.id == t.id } ?? {
            let n = Itinero.Traveler(name: t.name, team: t.team)
            n.id = t.id; n.trip = trip
            context.insert(n)
            return n
        }()
        m.name = t.name; m.team = t.team
    }

    static func upsert(_ d: TripSnapshot.Day, into trip: Trip, context: ModelContext) {
        let m = trip.allDays.first { $0.id == d.id } ?? {
            let n = Itinero.Day(date: d.date, title: d.title)
            n.id = d.id; n.trip = trip
            context.insert(n)
            return n
        }()
        m.date = d.date; m.title = d.title
    }

    static func upsert(_ c: TripSnapshot.Check, into trip: Trip, context: ModelContext) {
        let m = trip.allChecklist.first { $0.id == c.id } ?? {
            let n = ChecklistItem(title: c.title, group: c.group)
            n.id = c.id; n.trip = trip
            context.insert(n)
            return n
        }()
        m.title = c.title; m.group = c.group; m.isDone = c.isDone; m.sortOrder = c.sortOrder
        m.owner = c.ownerID.flatMap { id in trip.allTravelers.first { $0.id == id } }
    }

    static func upsert(_ i: TripSnapshot.Item, into trip: Trip, context: ModelContext) {
        let m = trip.allItems.first { $0.id == i.id } ?? {
            let n = ItineraryItem(title: i.title)
            n.id = i.id; n.trip = trip
            context.insert(n)
            return n
        }()
        if m.place != i.place { m.latitude = nil; m.longitude = nil }
        m.title = i.title; m.place = i.place; m.address = i.address; m.categoryRaw = i.categoryRaw; m.statusRaw = i.statusRaw
        m.startsAt = i.startsAt; m.endsAt = i.endsAt; m.timeNote = i.timeNote; m.timeZoneID = i.timeZoneID
        m.confirmation = i.confirmation; m.details = i.details; m.isOptional = i.isOptional; m.isMustDo = i.isMustDo
        m.cost = i.cost; m.currency = i.currency; m.isPaid = i.isPaid; m.isDone = i.isDone
        m.allAboardAt = i.allAboardAt; m.linkURLs = i.linkURLs; m.sortOrder = i.sortOrder
        if let dayID = i.dayID, let day = trip.allDays.first(where: { $0.id == dayID }) { m.day = day }
        m.attendees = trip.allTravelers.filter { i.attendeeIDs.contains($0.id) }
    }

    /// Removes one entity that was deleted remotely. Returns true if something was removed.
    @discardableResult
    static func remove(_ type: CloudRecordType, id: UUID, from trip: Trip, context: ModelContext) -> Bool {
        switch type {
        case .traveler: if let m = trip.allTravelers.first(where: { $0.id == id }) { context.delete(m); return true }
        case .day: if let m = trip.allDays.first(where: { $0.id == id }) { context.delete(m); return true }
        case .item: if let m = trip.allItems.first(where: { $0.id == id }) { context.delete(m); return true }
        case .check: if let m = trip.allChecklist.first(where: { $0.id == id }) { context.delete(m); return true }
        case .trip: return false   // a deleted trip record never deletes the local trip
        }
        return false
    }

    /// Safety net after a fetch: an item whose day hasn't arrived yet would otherwise be invisible.
    /// Re-links from the synced value when possible, else files it under the day of its start (or the first day).
    static func relinkOrphans(_ trip: Trip, links: [UUID: (day: UUID?, attendees: [UUID])], context: ModelContext) {
        for item in trip.allItems where item.day == nil {
            if let dayID = links[item.id]?.day, let d = trip.allDays.first(where: { $0.id == dayID }) {
                item.day = d
            } else {
                item.day = trip.day(for: item.startsAt ?? trip.startDate, context: context)
            }
            if let ids = links[item.id]?.attendees, (item.attendees ?? []).isEmpty, !ids.isEmpty {
                item.attendees = trip.allTravelers.filter { ids.contains($0.id) }
            }
        }
    }
}
