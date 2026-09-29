import XCTest
@testable import Itinero

final class SiteImportTests: XCTestCase {
    private let roster = ["Ann", "Ben", "Cy", "Di"]

    // MARK: notes

    func testEveryoneAndTagAndReservation() {
        let n = SiteImporter.parseNotes("All 4 — [Meal] — needs booking/reservation", roster: roster)
        XCTAssertTrue(n.attendees.isEmpty)
        XCTAssertEqual(n.tag, "Meal")
        XCTAssertTrue(n.needsReservation)
        XCTAssertTrue(n.remainder.isEmpty)
    }

    func testNamedAttendeesAndOptional() {
        let n = SiteImporter.parseNotes("Ann · Ben — [Activity]", roster: roster)
        XCTAssertEqual(n.attendees, ["Ann", "Ben"])
        XCTAssertFalse(n.isOptional)
        XCTAssertTrue(SiteImporter.parseNotes("All 4 (optional) — [Activity]", roster: roster).isOptional)
    }

    func testTeamSuffixAndTrailingText() {
        let n = SiteImporter.parseNotes("Cy · Di (Team 2) — needs booking/reservation", roster: roster)
        XCTAssertEqual(n.attendees, ["Cy", "Di"])
        XCTAssertTrue(n.needsReservation)
    }

    func testAttendeeFollowedByFreeText() {
        let n = SiteImporter.parseNotes("Ann · Ben · Cy check in Nov 20; Di joins later", roster: roster)
        XCTAssertEqual(n.attendees, ["Ann", "Ben", "Cy"])
        XCTAssertEqual(n.remainder, ["Cy check in Nov 20; Di joins later"])
    }

    func testNotesWithoutWhoStayAsRemainder() {
        let n = SiteImporter.parseNotes("Bring cash", roster: roster)
        XCTAssertTrue(n.attendees.isEmpty)
        XCTAssertEqual(n.remainder, ["Bring cash"])
    }

    // MARK: times

    func testTimeRanges() {
        func r(_ s: String) -> (Int, Int, Int, Int)? {
            guard let t = SiteImporter.parseTimeRange(s) else { return nil }
            return (t.start.0, t.start.1, t.end?.0 ?? -1, t.end?.1 ?? -1)
        }
        XCTAssertEqual(r("4:30–6:30pm")?.0, 16); XCTAssertEqual(r("4:30–6:30pm")?.2, 18)
        XCTAssertEqual(r("9:00–12:00pm")?.0, 9);  XCTAssertEqual(r("9:00–12:00pm")?.2, 12)
        XCTAssertEqual(r("10:00am–12:00pm")?.0, 10)
        XCTAssertEqual(r("11:30am–1:00pm")?.2, 13)
        XCTAssertEqual(r("1:00–4:00pm")?.0, 13)
        XCTAssertEqual(r("7:00pm")?.0, 19); XCTAssertEqual(r("7:00pm")?.2, -1)
        XCTAssertEqual(r("3:00pm+")?.0, 15)
        XCTAssertEqual(r("9:00pm–late")?.0, 21); XCTAssertEqual(r("9:00pm–late")?.2, -1)
        XCTAssertEqual(r("6:30am depart")?.0, 6)
        XCTAssertNil(r("Morning"))
    }

    // MARK: whole file

    private func file(_ items: String, days: String = "{}") -> Data {
        Data("""
        {"trip":{"name":"Test","destination":"Nowhere","kind":"land","start":"2026-11-13","end":"2026-11-20","timeZone":"Asia/Tokyo"},
         "travelers":[{"name":"Ann","team":"A"},{"name":"Ben","team":"B"}],
         "days":\(days),"items":[\(items)]}
        """.utf8)
    }

    func testActivityParsing() throws {
        let t = try SiteImporter.parse(file("""
        {"date":"2026-11-15","category":"activity","title":"Ramen","booked":false,
         "meta":["19:00","Ramen shop, Tokyo","7:00–8:00pm"],"notes":"Ann — [Meal]"}
        """))
        let i = try XCTUnwrap(t.items.first)
        XCTAssertEqual(i.category, .meal)
        XCTAssertEqual(i.status, .planned)
        XCTAssertEqual(i.place, "Ramen shop, Tokyo")
        XCTAssertEqual(i.attendeeNames, ["Ann"])
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(cal.component(.hour, from: try XCTUnwrap(i.startsAt)), 19)
        XCTAssertEqual(cal.component(.hour, from: try XCTUnwrap(i.endsAt)), 20)
        XCTAssertTrue(t.warnings.isEmpty)
    }

    func testConflictingStartTimeWarnsAndPrefersListedTime() throws {
        let t = try SiteImporter.parse(file("""
        {"date":"2026-11-16","category":"activity","title":"Morning wander","booked":false,
         "meta":["21:00","Old town","9:00–12:00pm"],"notes":"All 2 — [Activity]"}
        """))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(cal.component(.hour, from: try XCTUnwrap(t.items[0].startsAt)), 9)
        XCTAssertEqual(t.warnings.count, 1)
    }

    func testFlightUsesDepartureAirportZoneAndConfirmation() throws {
        let t = try SiteImporter.parse(file("""
        {"date":"2026-11-14","category":"flight","title":"Out","booked":true,
         "meta":["Acme 12","MCO → MSP","Nov 14, 6:15 AM","Conf: ABC123"],"notes":"Ann · Ben"}
        """))
        let i = t.items[0]
        XCTAssertEqual(i.category, .flight)
        XCTAssertEqual(i.status, .booked)
        XCTAssertEqual(i.confirmation, "ABC123")
        XCTAssertEqual(i.timeZoneID, "America/New_York")
        XCTAssertEqual(i.place, "MSP")
        // 6:15 AM Eastern on Nov 14 (EST, UTC-5) is 11:15 UTC.
        let utc = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: try XCTUnwrap(i.startsAt))
        XCTAssertEqual(utc.hour, 11); XCTAssertEqual(utc.minute, 15)
    }

    func testTrainAndUnknownDestinationAndNeedsBooking() throws {
        let t = try SiteImporter.parse(file("""
        {"date":"2026-11-27","category":"flight","title":"Bullet train","booked":false,
         "meta":["JR Shinkansen","A Station → B Station","Nov 27, 11:00 AM"],"notes":"All 2"},
        {"date":"2026-11-27","category":"flight","title":"Flight home","booked":false,"meta":["HND → ?"],"notes":"Ann"}
        """))
        XCTAssertEqual(t.items[0].category, .train)
        XCTAssertEqual(t.items[0].status, .needsBooking)
        XCTAssertEqual(t.items[1].category, .flight)
        XCTAssertTrue(t.warnings.contains { $0.message.contains("Destination") })
    }

    func testHotelBackwardsDatesWarnAndAreNotImported() throws {
        let t = try SiteImporter.parse(file("""
        {"date":"2026-11-15","category":"hotel","title":"Check in","booked":true,
         "meta":["Cozy Inn","Wed, Nov 25 → Fri, Nov 20","1-2-3 Main St, Tokyo","Conf: XYZ"],"notes":""}
        """))
        let i = t.items[0]
        XCTAssertEqual(i.category, .stay)
        XCTAssertEqual(i.place, "Cozy Inn")
        XCTAssertEqual(i.address, "1-2-3 Main St, Tokyo")
        XCTAssertNil(i.endsAt)
        XCTAssertTrue(t.warnings.contains { $0.message.contains("before check-in") })
    }

    func testCheckOutAndArriveAreLogisticsNotBookings() throws {
        let t = try SiteImporter.parse(file("""
        {"date":"2026-11-20","category":"hotel","title":"Pack up — check out","booked":false,"meta":[],"notes":"All 2"},
        {"date":"2026-11-15","category":"flight","title":"Arrive Tokyo — customs","booked":false,"meta":[],"notes":"Ann"}
        """))
        XCTAssertEqual(t.items[0].status, .planned)
        XCTAssertEqual(t.items[1].status, .planned)
    }

    func testTripHeaderAndDayTitles() throws {
        let t = try SiteImporter.parse(file("", days: #"{"2026-11-13":"Fly out"}"#))
        XCTAssertEqual(t.name, "Test")
        XCTAssertEqual(t.timeZoneID, "Asia/Tokyo")
        XCTAssertEqual(t.travelers.map(\.name), ["Ann", "Ben"])
        XCTAssertEqual(t.dayTitles["2026-11-13"], "Fly out")
        XCTAssertEqual(TripLogic.dayCount(start: t.start, end: t.end, calendar: { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }()), 8)
    }

    func testRejectsNonItineraryJSON() {
        XCTAssertThrowsError(try SiteImporter.parse(Data("{}".utf8)))
    }
}
