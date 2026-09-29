import Foundation
import CloudKit
import CryptoKit

/// The header fields of a trip that sync (everything except the child collections).
struct TripHeader: Codable, Equatable {
    var id: UUID
    var name: String
    var destination: String
    var kindRaw: String
    var startDate: Date
    var endDate: Date
    var timeZoneID: String
    var notes: String
    var cruiseLine: String
    var shipName: String
    var cabin: String
    var linkURLs: [String]
}

extension TripSnapshot {
    var header: TripHeader {
        TripHeader(id: id, name: name, destination: destination, kindRaw: kindRaw, startDate: startDate, endDate: endDate,
                   timeZoneID: timeZoneID, notes: notes, cruiseLine: cruiseLine, shipName: shipName, cabin: cabin, linkURLs: linkURLs)
    }
}

enum CloudRecordType: String, CaseIterable {
    case trip = "Trip", traveler = "Traveler", day = "Day", item = "Item", check = "Check"
    var prefix: String { rawValue.lowercased() }
}

struct LocalRecord: Equatable {
    let name: String
    let type: CloudRecordType
    let fingerprint: String
}

struct SyncPlan: Equatable {
    var save: [String] = []
    var delete: [String] = []
    var isEmpty: Bool { save.isEmpty && delete.isEmpty }
}

enum CloudRecords {
    static let container = "iCloud.com.matt.triptrac"

    // MARK: Names

    static func name(_ type: CloudRecordType, _ id: UUID) -> String { "\(type.prefix)-\(id.uuidString)" }

    static func parse(_ recordName: String) -> (type: CloudRecordType, id: UUID)? {
        guard let dash = recordName.firstIndex(of: "-") else { return nil }
        let prefix = String(recordName[..<dash])
        guard let type = CloudRecordType.allCases.first(where: { $0.prefix == prefix }),
              let id = UUID(uuidString: String(recordName[recordName.index(after: dash)...])) else { return nil }
        return (type, id)
    }

    /// One zone per trip so a trip can be shared (and stop being shared) on its own.
    static func zoneID(trip: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "trip-\(trip.uuidString)", ownerName: owner)
    }

    static func tripID(zone: CKRecordZone.ID) -> UUID? {
        guard zone.zoneName.hasPrefix("trip-") else { return nil }
        return UUID(uuidString: String(zone.zoneName.dropFirst(5)))
    }

    // MARK: Fingerprints & diff

    /// Stable content hash. Map-pin coordinates are a local cache, so they're excluded and never cause a sync.
    static func fingerprint<T: Encodable>(_ value: T) -> String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        let data = (try? e.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func localRecords(_ s: TripSnapshot) -> [LocalRecord] {
        var out = [LocalRecord(name: name(.trip, s.id), type: .trip, fingerprint: fingerprint(s.header))]
        out += s.travelers.map { LocalRecord(name: name(.traveler, $0.id), type: .traveler, fingerprint: fingerprint($0)) }
        out += s.days.map { LocalRecord(name: name(.day, $0.id), type: .day, fingerprint: fingerprint($0)) }
        out += s.items.map { i in
            var c = i; c.latitude = nil; c.longitude = nil
            return LocalRecord(name: name(.item, i.id), type: .item, fingerprint: fingerprint(c))
        }
        out += s.checklist.map { LocalRecord(name: name(.check, $0.id), type: .check, fingerprint: fingerprint($0)) }
        return out
    }

    /// What to send: changed/new records, and records that were synced before but no longer exist locally.
    /// The trip record itself is never deleted from here — removing a trip is not a sync operation.
    static func plan(local: [LocalRecord], synced: [String: String]) -> SyncPlan {
        var plan = SyncPlan()
        let localNames = Set(local.map(\.name))
        plan.save = local.filter { synced[$0.name] != $0.fingerprint }.map(\.name)
        plan.delete = synced.keys.filter { !localNames.contains($0) && parse($0)?.type != .trip }.sorted()
        return plan
    }

    enum Winner: Equatable { case local, server }

    /// Last writer wins. On a tie or missing information the server copy wins, so we never clobber shared data.
    static func resolve(localEditedAt: Date?, serverEditedAt: Date?) -> Winner {
        guard let l = localEditedAt else { return .server }
        guard let s = serverEditedAt else { return .local }
        return l > s ? .local : .server
    }

    // MARK: Snapshot → CKRecord

    static func makeRecord(named name: String, from s: TripSnapshot, zone: CKRecordZone.ID, base: CKRecord?, editedAt: Date) -> CKRecord? {
        guard let (type, id) = parse(name) else { return nil }
        let recordID = CKRecord.ID(recordName: name, zoneID: zone)
        let record = base ?? CKRecord(recordType: type.rawValue, recordID: recordID)
        record["lastEditedAt"] = editedAt as CKRecordValue
        switch type {
        case .trip:
            let h = s.header
            record["name"] = h.name as CKRecordValue; record["destination"] = h.destination as CKRecordValue
            record["kindRaw"] = h.kindRaw as CKRecordValue; record["startDate"] = h.startDate as CKRecordValue
            record["endDate"] = h.endDate as CKRecordValue; record["timeZoneID"] = h.timeZoneID as CKRecordValue
            record["notes"] = h.notes as CKRecordValue; record["cruiseLine"] = h.cruiseLine as CKRecordValue
            record["shipName"] = h.shipName as CKRecordValue; record["cabin"] = h.cabin as CKRecordValue
            record["linkURLs"] = h.linkURLs as CKRecordValue
        case .traveler:
            guard let t = s.travelers.first(where: { $0.id == id }) else { return nil }
            record["name"] = t.name as CKRecordValue; record["team"] = t.team as CKRecordValue
        case .day:
            guard let d = s.days.first(where: { $0.id == id }) else { return nil }
            record["date"] = d.date as CKRecordValue; record["title"] = d.title as CKRecordValue
        case .check:
            guard let c = s.checklist.first(where: { $0.id == id }) else { return nil }
            record["title"] = c.title as CKRecordValue; record["group"] = c.group as CKRecordValue
            record["isDone"] = (c.isDone ? 1 : 0) as CKRecordValue; record["sortOrder"] = c.sortOrder as CKRecordValue
            record["ownerID"] = c.ownerID?.uuidString as CKRecordValue?
        case .item:
            guard let i = s.items.first(where: { $0.id == id }) else { return nil }
            record["title"] = i.title as CKRecordValue; record["place"] = i.place as CKRecordValue
            record["address"] = i.address as CKRecordValue; record["categoryRaw"] = i.categoryRaw as CKRecordValue
            record["statusRaw"] = i.statusRaw as CKRecordValue
            record["startsAt"] = i.startsAt as CKRecordValue?; record["endsAt"] = i.endsAt as CKRecordValue?
            record["timeNote"] = i.timeNote as CKRecordValue; record["timeZoneID"] = i.timeZoneID as CKRecordValue
            record["confirmation"] = i.confirmation as CKRecordValue; record["details"] = i.details as CKRecordValue
            record["isOptional"] = (i.isOptional ? 1 : 0) as CKRecordValue; record["isMustDo"] = (i.isMustDo ? 1 : 0) as CKRecordValue
            record["cost"] = i.cost as CKRecordValue?; record["currency"] = i.currency as CKRecordValue
            record["isPaid"] = (i.isPaid ? 1 : 0) as CKRecordValue; record["isDone"] = (i.isDone ? 1 : 0) as CKRecordValue
            record["allAboardAt"] = i.allAboardAt as CKRecordValue?; record["linkURLs"] = i.linkURLs as CKRecordValue
            record["sortOrder"] = i.sortOrder as CKRecordValue
            record["dayID"] = i.dayID?.uuidString as CKRecordValue?
            record["attendeeIDs"] = i.attendeeIDs.map(\.uuidString) as CKRecordValue
        }
        if type != .trip {
            let tripRecord = CKRecord.ID(recordName: CloudRecords.name(.trip, s.id), zoneID: zone)
            record.parent = CKRecord.Reference(recordID: tripRecord, action: .none)
        }
        return record
    }

    // MARK: CKRecord → values

    static func header(from r: CKRecord) -> TripHeader? {
        guard let (type, id) = parse(r.recordID.recordName), type == .trip else { return nil }
        return TripHeader(id: id, name: r["name"] as? String ?? "", destination: r["destination"] as? String ?? "",
                          kindRaw: r["kindRaw"] as? String ?? TripKind.land.rawValue,
                          startDate: r["startDate"] as? Date ?? .now, endDate: r["endDate"] as? Date ?? .now,
                          timeZoneID: r["timeZoneID"] as? String ?? TimeZone.current.identifier,
                          notes: r["notes"] as? String ?? "", cruiseLine: r["cruiseLine"] as? String ?? "",
                          shipName: r["shipName"] as? String ?? "", cabin: r["cabin"] as? String ?? "",
                          linkURLs: r["linkURLs"] as? [String] ?? [])
    }

    static func traveler(from r: CKRecord) -> TripSnapshot.Traveler? {
        guard let (type, id) = parse(r.recordID.recordName), type == .traveler else { return nil }
        return .init(id: id, name: r["name"] as? String ?? "", team: r["team"] as? String ?? "")
    }

    static func day(from r: CKRecord) -> TripSnapshot.Day? {
        guard let (type, id) = parse(r.recordID.recordName), type == .day, let date = r["date"] as? Date else { return nil }
        return .init(id: id, date: date, title: r["title"] as? String ?? "")
    }

    static func check(from r: CKRecord) -> TripSnapshot.Check? {
        guard let (type, id) = parse(r.recordID.recordName), type == .check else { return nil }
        return .init(id: id, title: r["title"] as? String ?? "", group: r["group"] as? String ?? "To do",
                     isDone: (r["isDone"] as? Int ?? 0) != 0, sortOrder: r["sortOrder"] as? Int ?? 0,
                     ownerID: (r["ownerID"] as? String).flatMap(UUID.init(uuidString:)))
    }

    static func item(from r: CKRecord) -> TripSnapshot.Item? {
        guard let (type, id) = parse(r.recordID.recordName), type == .item else { return nil }
        var i = TripSnapshot.Item(id: id, title: r["title"] as? String ?? "")
        i.place = r["place"] as? String ?? ""; i.address = r["address"] as? String ?? ""
        i.categoryRaw = r["categoryRaw"] as? String ?? i.categoryRaw; i.statusRaw = r["statusRaw"] as? String ?? i.statusRaw
        i.startsAt = r["startsAt"] as? Date; i.endsAt = r["endsAt"] as? Date
        i.timeNote = r["timeNote"] as? String ?? ""; i.timeZoneID = r["timeZoneID"] as? String ?? ""
        i.confirmation = r["confirmation"] as? String ?? ""; i.details = r["details"] as? String ?? ""
        i.isOptional = (r["isOptional"] as? Int ?? 0) != 0; i.isMustDo = (r["isMustDo"] as? Int ?? 0) != 0
        i.cost = r["cost"] as? Double; i.currency = r["currency"] as? String ?? ""
        i.isPaid = (r["isPaid"] as? Int ?? 0) != 0; i.isDone = (r["isDone"] as? Int ?? 0) != 0
        i.allAboardAt = r["allAboardAt"] as? Date; i.linkURLs = r["linkURLs"] as? [String] ?? []
        i.sortOrder = r["sortOrder"] as? Int ?? 0
        i.dayID = (r["dayID"] as? String).flatMap(UUID.init(uuidString:))
        i.attendeeIDs = (r["attendeeIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        return i
    }

    static func editedAt(_ r: CKRecord) -> Date? { r["lastEditedAt"] as? Date }

    // MARK: System fields (change tags) persistence

    static func archiveSystemFields(_ r: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        r.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
