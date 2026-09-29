import XCTest
@testable import Itinero

final class Phase5LogicTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let ann = UUID(), ben = UUID(), day1 = UUID(), day2 = UUID()
    private var tokyo: TimeZone { TimeZone(identifier: "Asia/Tokyo")! }
    private func jst(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = tokyo
        return c.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    private func trip() -> TripSnapshot {
        var t = TripSnapshot(id: UUID(), name: "Test, Trip", destination: "Japan", kindRaw: "Land trip",
                             startDate: jst(15, 0), endDate: jst(16, 0), timeZoneID: "Asia/Tokyo")
        t.travelers = [.init(id: ann, name: "Ann", team: ""), .init(id: ben, name: "Ben", team: "")]
        t.days = [.init(id: day1, date: jst(15, 0), title: "Arrive"), .init(id: day2, date: jst(16, 0), title: "")]
        var ramen = TripSnapshot.Item(id: UUID(), title: "Ramen", place: "Shop", categoryRaw: "meal",
                                      startsAt: jst(15, 19), endsAt: jst(15, 20), timeZoneID: "Asia/Tokyo")
        ramen.attendeeIDs = [ann]; ramen.confirmation = "ABC"
        var temple = TripSnapshot.Item(id: UUID(), title: "Temple", startsAt: jst(15, 9), timeZoneID: "Asia/Tokyo")
        temple.attendeeIDs = []
        var inn = TripSnapshot.Item(id: UUID(), title: "Inn", categoryRaw: "stay", statusRaw: "booked", timeZoneID: "Asia/Tokyo")
        inn.endsAt = jst(16, 11); inn.dayID = day1
        ramen.dayID = day1; temple.dayID = day1
        t.items = [ramen, temple, inn]
        return t
    }

    // MARK: snapshot

    func testSnapshotJSONRoundTrip() throws {
        let t = trip()
        XCTAssertEqual(try TripSnapshot.decode(t.encoded()), t)
    }

    func testDecodingSiteExportFailsSoImporterFallsBack() {
        XCTAssertThrowsError(try TripSnapshot.decode(Data(#"{"trip":{},"items":[]}"#.utf8)))
    }

    // MARK: text

    func testTextGroupsByDayOrdersByTimeAndFiltersTraveler() {
        let all = ItineraryExporter.text(trip(), locale: us)
        let lines = all.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Test, Trip")
        XCTAssertTrue(all.contains("Sunday, Nov 15 — Arrive"))
        let temple = all.range(of: "Temple")!.lowerBound, ramen = all.range(of: "Ramen")!.lowerBound
        XCTAssertTrue(temple < ramen)
        XCTAssertTrue(all.contains("(conf ABC; Ann)"))
        let benOnly = ItineraryExporter.text(trip(), travelerID: ben, locale: us)
        XCTAssertFalse(benOnly.contains("Ramen"))
        XCTAssertTrue(benOnly.contains("Temple"))
        XCTAssertTrue(benOnly.hasPrefix("Test, Trip — Ben's plan"))
    }

    // MARK: ics

    func testICSStructureEscapingAndTimes() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let ics = ICSExporter.make(trip(), now: now)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("X-WR-CALNAME:Test\\, Trip"))
        XCTAssertTrue(ics.contains("DTSTART:20261115T100000Z"))   // 19:00 JST
        XCTAssertTrue(ics.contains("DTEND:20261115T110000Z"))
        XCTAssertTrue(ics.contains("DTSTART:20261115T000000Z"))   // 09:00 JST temple
        XCTAssertTrue(ics.contains("DTEND:20261115T010000Z"))     // default 1 hour
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20261115"))   // stay is all-day
        XCTAssertTrue(ics.contains("DTEND;VALUE=DATE:20261116"))
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 3)
        XCTAssertTrue(ics.contains("Confirmation: ABC"))
    }

    func testICSFiltersByTravelerAndSkipsCancelled() {
        var t = trip()
        t.items[1].statusRaw = "cancelled"
        let benICS = ICSExporter.make(t, travelerID: ben)
        XCTAssertFalse(benICS.contains("SUMMARY:Ramen"))
        XCTAssertFalse(benICS.contains("SUMMARY:Temple"))
        XCTAssertTrue(benICS.contains("SUMMARY:Inn"))
    }

    func testICSFoldsLongLinesAndEscapes() {
        let long = String(repeating: "abc", count: 60)
        let folded = ICSExporter.fold("SUMMARY:" + long)
        XCTAssertTrue(folded.dropFirst().allSatisfy { $0.hasPrefix(" ") })
        XCTAssertTrue(folded.allSatisfy { $0.utf8.count <= 75 })
        XCTAssertEqual(folded.enumerated().map { $0.offset == 0 ? $0.element : String($0.element.dropFirst()) }.joined(), "SUMMARY:" + long)
        XCTAssertEqual(ICSExporter.escape("a,b;c\nd\\"), "a\\,b\\;c\\nd\\\\")
    }

    // MARK: reminders

    func testReminderLeadTimesAndFiltering() {
        let now = jst(15, 0)
        var flight = TripSnapshot.Item(id: UUID(), title: "Flight", place: "HND", categoryRaw: "flight", statusRaw: "needsBooking",
                                       startsAt: jst(15, 12), timeZoneID: "Asia/Tokyo")
        let meal = TripSnapshot.Item(id: UUID(), title: "Meal", startsAt: jst(15, 13), timeZoneID: "Asia/Tokyo")
        var done = TripSnapshot.Item(id: UUID(), title: "Done", startsAt: jst(15, 14), timeZoneID: "Asia/Tokyo"); done.isDone = true
        let past = TripSnapshot.Item(id: UUID(), title: "Past", startsAt: jst(14, 12), timeZoneID: "Asia/Tokyo")
        let soon = TripSnapshot.Item(id: UUID(), title: "TooSoon", startsAt: now.addingTimeInterval(600), timeZoneID: "Asia/Tokyo")
        flight.attendeeIDs = []
        let plan = ReminderPlanner.plan([meal, flight, done, past, soon], now: now, locale: us)
        XCTAssertEqual(plan.map(\.title), ["Flight", "Meal"])
        XCTAssertEqual(plan[0].fireDate, jst(15, 9))               // 3h before
        XCTAssertEqual(plan[1].fireDate, jst(15, 12))              // 1h before
        XCTAssertTrue(plan[0].body.contains("HND"))
        XCTAssertTrue(plan[0].body.contains("not booked yet"))
        XCTAssertTrue(plan[0].body.contains("JST"))
    }

    func testReminderCapAndStableIDs() {
        let now = jst(1, 0)
        let items = (0..<100).map { i in TripSnapshot.Item(id: UUID(), title: "i\(i)", startsAt: now.addingTimeInterval(Double(7200 + i * 60)), timeZoneID: "Asia/Tokyo") }
        let plan = ReminderPlanner.plan(items, now: now)
        XCTAssertEqual(plan.count, ReminderPlanner.maxPending)
        XCTAssertEqual(plan.first?.title, "i0")
        XCTAssertTrue(plan.allSatisfy { $0.id.hasPrefix("tt-") })
    }

    func testAllAboardReminder() {
        let now = jst(20, 0)
        var port = TripSnapshot.Item(id: UUID(), title: "Cozumel", categoryRaw: "portDay", timeZoneID: "America/Cancun")
        port.allAboardAt = jst(20, 14)
        var later = port; later.id = UUID(); later.allAboardAt = jst(20, 1)   // fire time already passed
        let plan = ReminderPlanner.planAllAboard([port, later], now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate, jst(20, 12))
        XCTAssertTrue(plan[0].id.hasSuffix("-aboard"))
    }
}
