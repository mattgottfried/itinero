import Foundation

/// A plain-value copy of a whole trip. It is the unit of backup/restore, the input to the text and calendar
/// exporters, and (in Phase 4) the shape that maps to CloudKit records. Pure Codable — no SwiftData.
struct TripSnapshot: Codable, Equatable {
    struct Traveler: Codable, Equatable { var id: UUID; var name: String; var team: String }
    struct Day: Codable, Equatable { var id: UUID; var date: Date; var title: String }
    struct Item: Codable, Equatable {
        var id: UUID
        var title: String
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
        var latitude: Double?
        var longitude: Double?
        var sortOrder = 0
        var dayID: UUID?
        var attendeeIDs: [UUID] = []

        var category: ItemCategory { ItemCategory(rawValue: categoryRaw) ?? .other }
        var status: BookingStatus { BookingStatus(rawValue: statusRaw) ?? .planned }
    }
    struct Check: Codable, Equatable {
        var id: UUID; var title: String; var group: String; var isDone: Bool; var sortOrder: Int; var ownerID: UUID?
    }

    var version = 1
    var id: UUID
    var name: String
    var destination: String
    var kindRaw: String
    var startDate: Date
    var endDate: Date
    var timeZoneID: String
    var notes = ""
    var cruiseLine = ""
    var shipName = ""
    var cabin = ""
    var linkURLs: [String] = []
    var travelers: [Traveler] = []
    var days: [Day] = []
    var items: [Item] = []
    var checklist: [Check] = []

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }

    // MARK: JSON

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> TripSnapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(TripSnapshot.self, from: data)
    }
}

extension TripSnapshot.Item: Schedulable {}
