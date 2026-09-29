import Foundation
import SwiftData

enum TripKind: String, CaseIterable, Identifiable {
    case land = "Land trip"
    case cruise = "Cruise"
    var id: String { rawValue }
    var symbol: String { self == .cruise ? "ferry.fill" : "map.fill" }
}

@Model
final class Trip {
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var kindRaw: String
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \ItineraryItem.trip)
    var itinerary: [ItineraryItem] = []

    var kind: TripKind {
        get { TripKind(rawValue: kindRaw) ?? .land }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, destination: String, startDate: Date, endDate: Date,
         kind: TripKind = .land, notes: String = "") {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.kindRaw = kind.rawValue
        self.notes = notes
    }
}

@Model
final class ItineraryItem {
    var title: String
    var place: String
    var startsAt: Date
    var category: String
    var details: String
    var isCompleted: Bool
    var trip: Trip?

    init(title: String, place: String = "", startsAt: Date,
         category: String = "Activity", details: String = "", isCompleted: Bool = false) {
        self.title = title
        self.place = place
        self.startsAt = startsAt
        self.category = category
        self.details = details
        self.isCompleted = isCompleted
    }
}
