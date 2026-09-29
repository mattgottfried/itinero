import XCTest
@testable import Itinero

private struct Fake: Schedulable {
    var id = UUID()
    var title = "x"
    var place = ""
    var startsAt: Date?
    var endsAt: Date?
    var status: BookingStatus = .planned
    var category: ItemCategory = .activity
    var sortOrder = 0
    var attendeeIDs: [UUID] = []
    var isOptional = false
    var timeZoneID = ""
    var isDone = false
    var cost: Double?
    var currency = ""
    var isPaid = false
}

final class Phase2LogicTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func t(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }
    private let a = UUID(), b = UUID()

    // MARK: conflicts

    func testOverlapNeedsSharedTraveler() {
        let x = Fake(title: "X", startsAt: t(0), endsAt: t(60), attendeeIDs: [a])
        let y = Fake(title: "Y", startsAt: t(30), endsAt: t(90), attendeeIDs: [b])
        let z = Fake(title: "Z", startsAt: t(30), endsAt: t(90), attendeeIDs: [a, b])
        XCTAssertTrue(ScheduleIssues.detect([x, y], allTravelerIDs: [a, b]).isEmpty)
        XCTAssertEqual(ScheduleIssues.detect([x, z], allTravelerIDs: [a, b]).count, 1)
    }

    func testWholeGroupOverlapsEveryone() {
        let group = Fake(startsAt: t(0), endsAt: t(60))
        let one = Fake(startsAt: t(10), endsAt: t(20), attendeeIDs: [b])
        XCTAssertEqual(ScheduleIssues.detect([group, one], allTravelerIDs: [a, b]).count, 1)
    }

    func testBackToBackAndInstantsDoNotConflict() {
        let x = Fake(startsAt: t(0), endsAt: t(60))
        let next = Fake(startsAt: t(60), endsAt: t(120))
        let instantEdge = Fake(startsAt: t(60))
        let instantInside = Fake(startsAt: t(30))
        XCTAssertTrue(ScheduleIssues.detect([x, next], allTravelerIDs: []).isEmpty)
        XCTAssertTrue(ScheduleIssues.detect([x, instantEdge], allTravelerIDs: []).isEmpty)
        XCTAssertEqual(ScheduleIssues.detect([x, instantInside], allTravelerIDs: []).count, 1)
    }

    func testStaysAndCancelledAreIgnoredForOverlap() {
        let stay = Fake(startsAt: t(0), endsAt: t(600), category: .stay)
        let act = Fake(startsAt: t(30), endsAt: t(60))
        let cancelled = Fake(startsAt: t(30), endsAt: t(60), status: .cancelled)
        XCTAssertTrue(ScheduleIssues.detect([stay, act, cancelled], allTravelerIDs: []).isEmpty)
    }

    func testBookedStayWithoutCheckoutAndBackwardsItem() {
        let stay = Fake(title: "Inn", status: .booked, category: .stay)
        let pending = Fake(status: .needsBooking, category: .stay)
        let bad = Fake(title: "Odd", startsAt: t(60), endsAt: t(0))
        let kinds = ScheduleIssues.detect([stay, pending, bad], allTravelerIDs: []).map(\.kind)
        XCTAssertEqual(Set(kinds), [.missingCheckout, .endsBeforeStart])
        XCTAssertEqual(kinds.count, 2)
    }

    // MARK: budget

    func testBudgetTotalsSplitAndCurrencies() {
        let items = [
            Fake(cost: 1000, currency: "jpy", isPaid: true),                 // whole group of 2
            Fake(attendeeIDs: [a], cost: 300, currency: "JPY"),
            Fake(attendeeIDs: [a, b], cost: 50, currency: "USD"),
            Fake(status: .cancelled, cost: 999, currency: "USD"),
            Fake(cost: nil, currency: "USD"),
        ]
        let totals = BudgetLogic.totals(items, travelerIDs: [a, b])
        XCTAssertEqual(totals.map(\.currency), ["JPY", "USD"])
        XCTAssertEqual(totals[0].planned, 1300); XCTAssertEqual(totals[0].paid, 1000); XCTAssertEqual(totals[0].remaining, 300)
        XCTAssertEqual(totals[0].perTraveler[a], 800); XCTAssertEqual(totals[0].perTraveler[b], 500)
        XCTAssertEqual(totals[1].planned, 50); XCTAssertEqual(totals[1].perTraveler[a], 25)
    }

    func testItemsWithoutCostOnlyCountsBookables() {
        let items = [Fake(category: .flight), Fake(category: .flight, cost: 5), Fake(category: .meal)]
        XCTAssertEqual(BudgetLogic.itemsWithoutCost(items), 1)
    }

    func testCurrencyFormat() {
        XCTAssertTrue(BudgetLogic.format(1200, currency: "JPY").contains("1,200"))
        XCTAssertTrue(BudgetLogic.format(5, currency: "ZZZ").hasSuffix("ZZZ"))
    }

    // MARK: booking groups

    func testBookingGroupsBucketAndOrder() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = base
        let soon = Fake(title: "soon", startsAt: now.addingTimeInterval(5 * 86400), status: .needsBooking)
        let sooner = Fake(title: "sooner", startsAt: now.addingTimeInterval(2 * 86400), status: .needsBooking)
        let later = Fake(title: "later", startsAt: now.addingTimeInterval(90 * 86400), status: .needsBooking)
        let none = Fake(title: "none", status: .needsBooking)
        let ignored = Fake(title: "booked", startsAt: now, status: .booked)
        let groups = BookingGroups.group([later, soon, none, ignored, sooner], now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.bucket), [.urgent, .later, .undated])
        XCTAssertEqual(groups[0].items.map(\.title), ["sooner", "soon"])
    }

    // MARK: maps, links, search

    func testMapQueryPrefersAddress() {
        XCTAssertEqual(MapLinks.query(place: "Inn", address: "1-2-3 Main St, Tokyo"), "Inn, 1-2-3 Main St, Tokyo")
        XCTAssertEqual(MapLinks.query(place: "", address: "1 Main St"), "1 Main St")
        XCTAssertEqual(MapLinks.query(place: "Meiji Jingu, Tokyo", address: ""), "Meiji Jingu, Tokyo")
        XCTAssertNil(MapLinks.query(place: " ", address: ""))
    }

    func testMapURLsEncodeAndUseTransit() throws {
        let s = try XCTUnwrap(MapLinks.search("Café & Bar, Tokyo"))
        XCTAssertEqual(URLComponents(url: s, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Café & Bar, Tokyo")
        let d = try XCTUnwrap(MapLinks.transitDirections(from: "A", to: "B C"))
        XCTAssertTrue(d.absoluteString.contains("dirflg=r"))
        XCTAssertEqual(URLComponents(url: d, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "daddr" }?.value, "B C")
    }

    func testLinkNormalizer() {
        XCTAssertEqual(LinkNormalizer.normalize("example.com/tickets")?.absoluteString, "https://example.com/tickets")
        XCTAssertEqual(LinkNormalizer.normalize(" http://a.co ")?.scheme, "http")
        XCTAssertNil(LinkNormalizer.normalize("not a link"))
        XCTAssertNil(LinkNormalizer.normalize("javascript:alert(1)"))
        XCTAssertNil(LinkNormalizer.normalize("localhost"))
        XCTAssertNil(LinkNormalizer.normalize(""))
    }

    func testSearchIgnoresCaseAccentsAndNeedsAllWords() {
        XCTAssertTrue(SearchLogic.matches("pokemon cafe", in: ["Pokémon Café", "Tokyo"]))
        XCTAssertTrue(SearchLogic.matches("abc123", in: ["Flight", "Conf ABC123"]))
        XCTAssertFalse(SearchLogic.matches("ramen osaka", in: ["Ramen", "Tokyo"]))
        XCTAssertTrue(SearchLogic.matches("  ", in: ["anything"]))
    }

    // MARK: time display, run state, port

    func testYourTimeOnlyWhenOffsetsDiffer() {
        let ny = TimeZone(identifier: "America/New_York")!, tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let d = Date(timeIntervalSince1970: 1_794_654_900) // 2026-11-14 11:15 UTC
        XCTAssertNil(TimeDisplay.yourTime(for: d, itemZone: ny, yourZone: ny))
        let text = TimeDisplay.yourTime(for: d, itemZone: ny, yourZone: tokyo, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text?.contains("8:15") == true, text ?? "nil")
    }

    func testTokyoIsAbbreviatedJST() {
        XCTAssertEqual(TimeDisplay.zoneAbbreviation(TimeZone(identifier: "Asia/Tokyo")!, at: .now), "JST")
    }

    func testRunState() {
        let timed = Fake(startsAt: t(0), endsAt: t(60))
        XCTAssertEqual(ItineraryLogic.runState(timed, now: t(-1)), .upcoming)
        XCTAssertEqual(ItineraryLogic.runState(timed, now: t(30)), .happeningNow)
        XCTAssertEqual(ItineraryLogic.runState(timed, now: t(61)), .past)
        let instant = Fake(startsAt: t(0))
        XCTAssertEqual(ItineraryLogic.runState(instant, now: t(59)), .happeningNow)
        XCTAssertEqual(ItineraryLogic.runState(instant, now: t(61)), .past)
        XCTAssertEqual(ItineraryLogic.runState(Fake(), now: t(0)), .upcoming)
    }

    func testProgressIgnoresCancelled() {
        let p = ItineraryLogic.progress([Fake(isDone: true), Fake(), Fake(status: .cancelled, isDone: true)])
        XCTAssertEqual(p.done, 1); XCTAssertEqual(p.total, 2)
    }

    func testAllAboardTone() {
        let ship = t(600)
        XCTAssertEqual(PortLogic.allAboardTone(ship, now: t(0)), .caution)
        XCTAssertEqual(PortLogic.allAboardTone(ship, now: t(500)), .alert)
        XCTAssertEqual(PortLogic.allAboardTone(ship, now: t(601)), .bad)
    }

    func testNextUpSkipsDoneFlag() {
        let done = Fake(startsAt: t(10), isDone: true)
        let open = Fake(title: "open", startsAt: t(20))
        XCTAssertEqual(ItineraryLogic.nextUp([done, open], now: t(0))?.title, "open")
    }
}
