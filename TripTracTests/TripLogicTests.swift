import XCTest
@testable import TripTrac

final class TripLogicTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private func date(_ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    func testPhase() {
        let start = date(11, 13), end = date(11, 27)
        XCTAssertEqual(TripLogic.phase(start: start, end: end, now: date(10, 1), calendar: cal), .upcoming)
        XCTAssertEqual(TripLogic.phase(start: start, end: end, now: date(11, 13, 0), calendar: cal), .inProgress)
        XCTAssertEqual(TripLogic.phase(start: start, end: end, now: date(11, 27, 23), calendar: cal), .inProgress)
        XCTAssertEqual(TripLogic.phase(start: start, end: end, now: date(11, 28, 1), calendar: cal), .past)
    }

    func testDaysUntilIgnoresTimeOfDay() {
        XCTAssertEqual(TripLogic.daysUntil(date(11, 13, 6), now: date(11, 12, 23), calendar: cal), 1)
        XCTAssertEqual(TripLogic.daysUntil(date(11, 13), now: date(11, 13, 20), calendar: cal), 0)
        XCTAssertEqual(TripLogic.daysUntil(date(11, 10), now: date(11, 13), calendar: cal), -3)
    }

    func testDayCountIsInclusive() {
        XCTAssertEqual(TripLogic.dayCount(start: date(11, 13), end: date(11, 27), calendar: cal), 15)
        XCTAssertEqual(TripLogic.dayCount(start: date(11, 13), end: date(11, 13), calendar: cal), 1)
    }
}
