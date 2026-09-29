import XCTest
@testable import Itinero

private struct Fake: Schedulable {
    var startsAt: Date?
    var endsAt: Date?
    var status: BookingStatus = .planned
    var category: ItemCategory = .activity
    var sortOrder = 0
    var attendeeIDs: [UUID] = []
    var isOptional = false
    var timeZoneID = ""
    var id = UUID()
    var title = ""
    var place = ""
    var isDone = false
    var cost: Double?
    var currency = ""
    var isPaid = false
}

final class ItineraryLogicTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c
    }()
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    func testSortByTimeThenOrder() {
        let items = [Fake(startsAt: at(15, 19), sortOrder: 1), Fake(startsAt: at(15, 9), sortOrder: 2),
                     Fake(startsAt: at(15, 9), sortOrder: 0)]
        XCTAssertEqual(ItineraryLogic.sorted(items, calendar: cal).map(\.sortOrder), [0, 2, 1])
    }

    func testUntimedStayLeadsDayAndOtherUntimedFallAtNoon() {
        let stay = Fake(category: .stay, sortOrder: 5)
        let untimed = Fake(sortOrder: 1)
        let morning = Fake(startsAt: at(15, 8), sortOrder: 2)
        let evening = Fake(startsAt: at(15, 18), sortOrder: 3)
        let sorted = ItineraryLogic.sorted([evening, untimed, morning, stay], calendar: cal)
        XCTAssertEqual(sorted.map(\.sortOrder), [5, 2, 1, 3])
    }

    func testSortUsesEachItemsOwnTimeZone() {
        // 6:15 AM Eastern (11:15 UTC) and 10:40 AM Central (16:40 UTC) on Nov 14. In Tokyo terms the
        // Central flight lands on the next day at 01:40 and would sort first; by local wall clock it must not.
        let orl = Fake(startsAt: Date(timeIntervalSince1970: 1_794_654_900), sortOrder: 0, timeZoneID: "America/New_York")
        let msp = Fake(startsAt: Date(timeIntervalSince1970: 1_794_654_900 + 5 * 3600 + 25 * 60), sortOrder: 1, timeZoneID: "America/Chicago")
        XCTAssertEqual(ItineraryLogic.sorted([msp, orl], calendar: cal).map(\.sortOrder), [0, 1])
    }

    func testVisibilityForTraveler() {
        let a = UUID(), b = UUID()
        XCTAssertTrue(ItineraryLogic.isVisible(Fake(attendeeIDs: []), for: a))
        XCTAssertTrue(ItineraryLogic.isVisible(Fake(attendeeIDs: [a]), for: a))
        XCTAssertFalse(ItineraryLogic.isVisible(Fake(attendeeIDs: [b]), for: a))
        XCTAssertTrue(ItineraryLogic.isVisible(Fake(attendeeIDs: [b]), for: nil))
    }

    func testSummaryCountsAndUrgency() {
        let now = at(1, 12) // Nov 1
        let items = [
            Fake(startsAt: at(5, 10), status: .needsBooking),      // 4 days → urgent
            Fake(startsAt: at(20, 10), status: .needsBooking),     // 19 days → urgent (window 30)
            Fake(startsAt: nil, status: .needsBooking),            // needs booking, no date → not urgent
            Fake(status: .booked), Fake(status: .done),
            Fake(status: .cancelled), Fake(status: .idea), Fake(status: .planned),
        ]
        let s = ItineraryLogic.summary(items, now: now, calendar: cal)
        XCTAssertEqual(s, BookingSummary(total: 6, booked: 2, needsBooking: 3, urgent: 2))
    }

    func testNextUpSkipsDoneAndFindsRunningItem() {
        let items = [
            Fake(startsAt: at(15, 9), status: .done, sortOrder: 0),
            Fake(startsAt: at(15, 10), endsAt: at(15, 12), sortOrder: 1),   // running at 11
            Fake(startsAt: at(15, 14), sortOrder: 2),
            Fake(startsAt: nil, sortOrder: 3),
        ]
        XCTAssertEqual(ItineraryLogic.nextUp(items, now: at(15, 11))?.sortOrder, 1)
        XCTAssertEqual(ItineraryLogic.nextUp(items, now: at(15, 13))?.sortOrder, 2)
        XCTAssertNil(ItineraryLogic.nextUp(items, now: at(15, 15)))
    }
}
