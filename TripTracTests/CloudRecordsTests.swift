import XCTest
import CloudKit
@testable import TripTrac

final class CloudRecordsTests: XCTestCase {
    private let tripID = UUID(), ann = UUID(), dayID = UUID(), itemID = UUID(), checkID = UUID()
    private var zone: CKRecordZone.ID { CloudRecords.zoneID(trip: tripID) }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot() -> TripSnapshot {
        var s = TripSnapshot(id: tripID, name: "Japan", destination: "Japan", kindRaw: "Land trip", startDate: t0,
                             endDate: t0.addingTimeInterval(86400 * 14), timeZoneID: "Asia/Tokyo")
        s.notes = "n"; s.linkURLs = ["https://a.co"]
        s.travelers = [.init(id: ann, name: "Ann", team: "T1")]
        s.days = [.init(id: dayID, date: t0, title: "Arrive")]
        var i = TripSnapshot.Item(id: itemID, title: "Ramen", place: "Shop", categoryRaw: "meal", statusRaw: "booked",
                                  startsAt: t0.addingTimeInterval(3600), endsAt: t0.addingTimeInterval(7200), timeZoneID: "Asia/Tokyo")
        i.cost = 1200.5; i.currency = "JPY"; i.isPaid = true; i.isDone = true; i.isOptional = true; i.isMustDo = true
        i.confirmation = "ABC"; i.details = "d"; i.linkURLs = ["https://b.co"]; i.sortOrder = 7
        i.dayID = dayID; i.attendeeIDs = [ann]; i.allAboardAt = t0
        s.items = [i]
        s.checklist = [.init(id: checkID, title: "Passport", group: "Documents", isDone: true, sortOrder: 2, ownerID: ann)]
        return s
    }

    // MARK: names

    func testNamesRoundTrip() {
        for type in CloudRecordType.allCases {
            let n = CloudRecords.name(type, itemID)
            let parsed = CloudRecords.parse(n)
            XCTAssertEqual(parsed?.type, type); XCTAssertEqual(parsed?.id, itemID)
        }
        XCTAssertNil(CloudRecords.parse("nonsense"))
        XCTAssertNil(CloudRecords.parse("item-not-a-uuid"))
        XCTAssertEqual(CloudRecords.tripID(zone: zone), tripID)
        XCTAssertNil(CloudRecords.tripID(zone: CKRecordZone.ID(zoneName: "other", ownerName: CKCurrentUserDefaultName)))
    }

    // MARK: records

    func testItemRecordRoundTrip() throws {
        let s = snapshot()
        let name = CloudRecords.name(.item, itemID)
        let r = try XCTUnwrap(CloudRecords.makeRecord(named: name, from: s, zone: zone, base: nil, editedAt: t0))
        XCTAssertEqual(r.recordType, "Item")
        XCTAssertEqual(r.parent?.recordID.recordName, CloudRecords.name(.trip, tripID))
        XCTAssertEqual(CloudRecords.editedAt(r), t0)
        XCTAssertEqual(CloudRecords.item(from: r), s.items[0])
    }

    func testOptionalFieldsClearWhenNil() throws {
        var s = snapshot()
        let name = CloudRecords.name(.item, itemID)
        let r = try XCTUnwrap(CloudRecords.makeRecord(named: name, from: s, zone: zone, base: nil, editedAt: t0))
        s.items[0].endsAt = nil; s.items[0].cost = nil; s.items[0].dayID = nil
        let r2 = try XCTUnwrap(CloudRecords.makeRecord(named: name, from: s, zone: zone, base: r, editedAt: t0))
        let back = try XCTUnwrap(CloudRecords.item(from: r2))
        XCTAssertNil(back.endsAt); XCTAssertNil(back.cost); XCTAssertNil(back.dayID)
    }

    func testTripTravelerDayCheckRoundTrip() throws {
        let s = snapshot()
        let trip = try XCTUnwrap(CloudRecords.makeRecord(named: CloudRecords.name(.trip, tripID), from: s, zone: zone, base: nil, editedAt: t0))
        XCTAssertNil(trip.parent)
        XCTAssertEqual(CloudRecords.header(from: trip), s.header)
        let tr = try XCTUnwrap(CloudRecords.makeRecord(named: CloudRecords.name(.traveler, ann), from: s, zone: zone, base: nil, editedAt: t0))
        XCTAssertEqual(CloudRecords.traveler(from: tr), s.travelers[0])
        let day = try XCTUnwrap(CloudRecords.makeRecord(named: CloudRecords.name(.day, dayID), from: s, zone: zone, base: nil, editedAt: t0))
        XCTAssertEqual(CloudRecords.day(from: day), s.days[0])
        let chk = try XCTUnwrap(CloudRecords.makeRecord(named: CloudRecords.name(.check, checkID), from: s, zone: zone, base: nil, editedAt: t0))
        XCTAssertEqual(CloudRecords.check(from: chk), s.checklist[0])
    }

    func testMakeRecordForMissingEntityIsNil() {
        XCTAssertNil(CloudRecords.makeRecord(named: CloudRecords.name(.item, UUID()), from: snapshot(), zone: zone, base: nil, editedAt: t0))
    }

    func testSystemFieldsRoundTrip() throws {
        let r = CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: CloudRecords.name(.item, itemID), zoneID: zone))
        let restored = try XCTUnwrap(CloudRecords.record(fromSystemFields: CloudRecords.archiveSystemFields(r)))
        XCTAssertEqual(restored.recordID, r.recordID)
        XCTAssertEqual(restored.recordType, "Item")
    }

    // MARK: fingerprints & plan

    func testFingerprintsIgnoreCoordinatesButNotContent() {
        var s = snapshot()
        let a = CloudRecords.localRecords(s)
        s.items[0].latitude = 35.6; s.items[0].longitude = 139.7
        XCTAssertEqual(CloudRecords.localRecords(s), a)
        s.items[0].title = "Sushi"
        XCTAssertNotEqual(CloudRecords.localRecords(s), a)
        XCTAssertEqual(a.count, 5)
    }

    func testPlanSavesChangedAndDeletesMissingButNeverTheTrip() {
        var s = snapshot()
        let synced = Dictionary(uniqueKeysWithValues: CloudRecords.localRecords(s).map { ($0.name, $0.fingerprint) })
        XCTAssertTrue(CloudRecords.plan(local: CloudRecords.localRecords(s), synced: synced).isEmpty)

        s.items[0].isDone = false
        s.checklist = []
        let plan = CloudRecords.plan(local: CloudRecords.localRecords(s), synced: synced)
        XCTAssertEqual(plan.save, [CloudRecords.name(.item, itemID)])
        XCTAssertEqual(plan.delete, [CloudRecords.name(.check, checkID)])

        // Even if the local trip vanished from the list, the trip record is not scheduled for deletion.
        let none = CloudRecords.plan(local: [], synced: synced)
        XCTAssertFalse(none.delete.contains(CloudRecords.name(.trip, tripID)))
    }

    func testNewTripPlansEverythingAsSave() {
        let plan = CloudRecords.plan(local: CloudRecords.localRecords(snapshot()), synced: [:])
        XCTAssertEqual(plan.save.count, 5)
        XCTAssertTrue(plan.delete.isEmpty)
    }

    func testConflictResolution() {
        XCTAssertEqual(CloudRecords.resolve(localEditedAt: t0.addingTimeInterval(10), serverEditedAt: t0), .local)
        XCTAssertEqual(CloudRecords.resolve(localEditedAt: t0, serverEditedAt: t0.addingTimeInterval(10)), .server)
        XCTAssertEqual(CloudRecords.resolve(localEditedAt: t0, serverEditedAt: t0), .server)
        XCTAssertEqual(CloudRecords.resolve(localEditedAt: nil, serverEditedAt: t0), .server)
        XCTAssertEqual(CloudRecords.resolve(localEditedAt: t0, serverEditedAt: nil), .local)
    }
}
