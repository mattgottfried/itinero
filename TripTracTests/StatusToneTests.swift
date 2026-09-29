import XCTest
@testable import TripTrac

final class StatusToneTests: XCTestCase {
    func testBookedAndDoneAreGood() {
        XCTAssertEqual(statusTone(for: .booked, daysUntil: 3), .good)
        XCTAssertEqual(statusTone(for: .done, daysUntil: nil), .good)
    }

    func testNeedsBookingEscalatesInsideWindow() {
        XCTAssertEqual(statusTone(for: .needsBooking, daysUntil: nil), .caution)
        XCTAssertEqual(statusTone(for: .needsBooking, daysUntil: bookingUrgencyWindowDays + 1), .caution)
        XCTAssertEqual(statusTone(for: .needsBooking, daysUntil: bookingUrgencyWindowDays), .alert)
        XCTAssertEqual(statusTone(for: .needsBooking, daysUntil: -1), .alert)
    }

    func testIdeaAndCancelledAreNeutral() {
        XCTAssertEqual(statusTone(for: .idea, daysUntil: 5), .neutral)
        XCTAssertEqual(statusTone(for: .cancelled, daysUntil: 5), .neutral)
    }

    func testEveryStatusHasDistinctSymbol() {
        let symbols = BookingStatus.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }
}
