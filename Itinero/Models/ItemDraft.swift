import Foundation
import SwiftData

/// A plain-value copy of an item: the editor works on this, and delete-with-undo restores from it.
struct ItemDraft: Equatable {
    var id = UUID()
    var title = ""
    var category: ItemCategory = .activity
    var status: BookingStatus = .planned
    var dayDate = Date()
    var startsAt: Date?
    var endsAt: Date?
    var timeNote = ""
    var place = ""
    var address = ""
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
    var sortOrder = 0
    var attendeeIDs: Set<UUID> = []

    init(dayDate: Date) { self.dayDate = dayDate }

    init(item: ItineraryItem) {
        id = item.id
        title = item.title
        category = item.category
        status = item.status
        dayDate = item.day?.date ?? item.startsAt ?? .now
        startsAt = item.startsAt
        endsAt = item.endsAt
        timeNote = item.timeNote
        place = item.place
        address = item.address
        confirmation = item.confirmation
        details = item.details
        isOptional = item.isOptional
        isMustDo = item.isMustDo
        cost = item.cost
        currency = item.currency
        isPaid = item.isPaid
        isDone = item.isDone
        allAboardAt = item.allAboardAt
        linkURLs = item.linkURLs
        sortOrder = item.sortOrder
        attendeeIDs = Set(item.allAttendees.map(\.id))
    }

    /// Copies the draft onto `item`, creating the item's Day if needed.
    func apply(to item: ItineraryItem, trip: Trip, context: ModelContext) {
        item.id = id
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.category = category
        item.status = status
        item.startsAt = startsAt
        item.endsAt = endsAt
        item.timeNote = timeNote
        if item.place != place { item.latitude = nil; item.longitude = nil }
        item.place = place
        item.address = address
        item.confirmation = confirmation
        item.details = details
        item.isOptional = isOptional
        item.isMustDo = isMustDo
        item.cost = cost
        item.currency = currency
        item.isPaid = isPaid
        item.isDone = isDone
        item.allAboardAt = allAboardAt
        item.linkURLs = linkURLs
        item.sortOrder = sortOrder
        item.timeZoneID = trip.timeZoneID
        item.trip = trip
        item.day = trip.day(for: dayDate, context: context)
        item.attendees = trip.allTravelers.filter { attendeeIDs.contains($0.id) }
    }
}

extension Trip {
    /// The Day for a calendar date in the trip's time zone, created on first use.
    func day(for date: Date, context: ModelContext) -> Day {
        let start = calendar.startOfDay(for: date)
        if let existing = allDays.first(where: { $0.date == start }) { return existing }
        let day = Day(date: start)
        day.trip = self
        context.insert(day)
        return day
    }
}
