import Foundation

/// What the home-screen widget shows. The app writes this into the shared App Group container; the widget
/// only ever reads it, so the widget never needs the SwiftData store.
struct NextUpSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var place: String
        var startsAt: Date
        var timeZoneID: String
        var symbol: String
        var statusLabel: String
        var isBooked: Bool
    }
    var tripName: String
    var tripStart: Date
    var tripEnd: Date
    var generatedAt: Date
    var entries: [Entry]

    static let appGroup = "group.com.matt.itinero"
    static let fileName = "nextup.json"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    static func load() -> NextUpSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(NextUpSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
