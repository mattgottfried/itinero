import XCTest
@testable import TripTrac

/// Sanity-checks the real (git-ignored) itinerary export when it exists on this machine.
final class RealItineraryTests: XCTestCase {
    func testJapanExportParsesCleanly() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("private/japan-2026.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("No private itinerary export on this machine") }
        let trip = try SiteImporter.parse(data)
        XCTAssertEqual(trip.items.count, 61)
        XCTAssertEqual(trip.items.filter { $0.status == .booked }.count, 7)
        XCTAssertEqual(trip.travelers.count, 7)
        XCTAssertEqual(trip.dayTitles.count, 15)
        for w in trip.warnings { print("IMPORT-WARNING | \(w.item) | \(w.message)") }
        // Every attendee name must resolve to a traveler.
        let roster = Set(trip.travelers.map(\.name))
        for item in trip.items { XCTAssertTrue(Set(item.attendeeNames).isSubset(of: roster), item.title) }
    }
}
