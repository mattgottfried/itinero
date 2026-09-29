import Foundation
import CloudKit
import SwiftData
import SwiftUI

/// Persistent bookkeeping for sync. Losing this file is safe: the next reconcile just re-sends everything.
struct CloudSyncState: Codable {
    var privateEngine: CKSyncEngine.State.Serialization?
    var sharedEngine: CKSyncEngine.State.Serialization?
    /// tripID → recordName → fingerprint of the content last confirmed synced.
    var fingerprints: [String: [String: String]] = [:]
    /// recordName → archived CKRecord system fields (change tags) from the server.
    var systemFields: [String: Data] = [:]
    /// recordName → when we last changed it locally (drives last-writer-wins).
    var lastEdited: [String: Date] = [:]
    /// Trips removed on this device; remote changes for them are ignored so they don't reappear.
    var tombstones: [String] = []
}

/// Family sharing: mirrors opted-in trips to CloudKit (one record zone per trip, shared with CKShare) using
/// CKSyncEngine. Opt-in per trip; nothing here runs until a trip is turned on or a share is accepted.
///
/// Safety rules: remote changes never delete a whole trip; a trip being un-shared or deleted in iCloud keeps
/// its local copy; deleting a trip on this device never deletes the shared copy.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    @Published private(set) var status = ""
    @Published private(set) var accountStatus: CKAccountStatus?

    private var modelContainer: ModelContainer?
    private var ckContainer: CKContainer?
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?
    private var privateDelegate: EngineDelegate?
    private var sharedDelegate: EngineDelegate?
    private var state = CloudSyncState()
    /// In-memory only: what we've already queued, so a 30 s reconcile doesn't re-stamp edit times.
    private var queuedSaves: [String: String] = [:]
    private var queuedDeletes: Set<String> = []
    /// What each in-flight record looked like when it was built.
    private var sending: [String: String] = [:]
    private var linkHints: [UUID: (day: UUID?, attendees: [UUID])] = [:]

    private var context: ModelContext? { modelContainer?.mainContext }

    // MARK: Lifecycle

    func start(container: ModelContainer) {
        guard modelContainer == nil else { return }
        modelContainer = container
        loadState()
        let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
        if trips.contains(where: \.cloudSync) || state.privateEngine != nil || state.sharedEngine != nil { ensureEngines() }
    }

    private func ensureEngines() {
        guard privateEngine == nil else { return }
        let c = CKContainer(identifier: CloudRecords.container)
        ckContainer = c
        let pd = EngineDelegate(scope: .private, owner: self), sd = EngineDelegate(scope: .shared, owner: self)
        privateDelegate = pd; sharedDelegate = sd
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(database: c.privateCloudDatabase, stateSerialization: state.privateEngine, delegate: pd))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(database: c.sharedCloudDatabase, stateSerialization: state.sharedEngine, delegate: sd))
        Task { accountStatus = try? await c.accountStatus() }
    }

    func refreshAccountStatus() async {
        ensureEngines()
        accountStatus = try? await ckContainer?.accountStatus()
    }

    /// Turn sync on for a trip I own. Existing content is uploaded; nothing local changes.
    func enable(_ trip: Trip) {
        ensureEngines()
        trip.cloudSync = true
        trip.cloudOwnerName = ""
        state.tombstones.removeAll { $0 == trip.id.uuidString }
        state.fingerprints[trip.id.uuidString] = [:]
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecords.zoneID(trip: trip.id)))])
        reconcile()
    }

    /// Stop syncing this trip. Local data and the cloud copy are both left as they are.
    func disable(_ trip: Trip) {
        trip.cloudSync = false
        state.fingerprints[trip.id.uuidString] = nil
        saveState()
    }

    /// Call before deleting a synced trip locally so it doesn't come back from the cloud.
    func forget(_ trip: Trip) {
        guard trip.cloudSync else { return }
        state.tombstones.append(trip.id.uuidString)
        state.fingerprints[trip.id.uuidString] = nil
        saveState()
    }

    // MARK: Local changes → pending

    /// Diffs every synced trip against what was last confirmed and queues the difference. Cheap; run often.
    func reconcile() {
        guard let context, privateEngine != nil else { return }
        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter(\.cloudSync)
        var changed = false
        for trip in trips {
            let key = trip.id.uuidString
            let local = CloudRecords.localRecords(TripSnapshot(trip: trip))
            let plan = CloudRecords.plan(local: local, synced: state.fingerprints[key] ?? [:])
            let zone = CloudRecords.zoneID(trip: trip.id, owner: zoneOwner(trip))
            var pending: [CKSyncEngine.PendingRecordZoneChange] = []
            let fp = Dictionary(uniqueKeysWithValues: local.map { ($0.name, $0.fingerprint) })
            for name in plan.save where queuedSaves[name] != fp[name] {
                queuedSaves[name] = fp[name]
                state.lastEdited[name] = .now
                pending.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: zone)))
            }
            for name in plan.delete where !queuedDeletes.contains(name) {
                queuedDeletes.insert(name)
                pending.append(.deleteRecord(CKRecord.ID(recordName: name, zoneID: zone)))
            }
            if !pending.isEmpty { engine(for: trip)?.state.add(pendingRecordZoneChanges: pending); changed = true }
        }
        if changed { saveState() }
    }

    func syncNow() async {
        ensureEngines()
        reconcile()
        try? await privateEngine?.fetchChanges()
        try? await sharedEngine?.fetchChanges()
        try? await privateEngine?.sendChanges()
        try? await sharedEngine?.sendChanges()
    }

    private func zoneOwner(_ trip: Trip) -> String { trip.cloudOwnerName.isEmpty ? CKCurrentUserDefaultName : trip.cloudOwnerName }
    private func engine(for trip: Trip) -> CKSyncEngine? { trip.cloudOwnerName.isEmpty ? privateEngine : sharedEngine }

    // MARK: Sharing

    /// Makes sure the trip is uploaded, then returns its (new or existing) CKShare for UICloudSharingController.
    func prepareShare(for trip: Trip) async throws -> (CKShare, CKContainer) {
        ensureEngines()
        guard let c = ckContainer, let engine = privateEngine else { throw CKError(.notAuthenticated) }
        if !trip.cloudSync { enable(trip) }
        reconcile()
        try await engine.sendChanges()
        let rootID = CKRecord.ID(recordName: CloudRecords.name(.trip, trip.id), zoneID: CloudRecords.zoneID(trip: trip.id))
        let db = c.privateCloudDatabase
        let root = try await db.record(for: rootID)
        if let ref = root.share, let existing = try await db.record(for: ref.recordID) as? CKShare { return (existing, c) }
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = trip.name as CKRecordValue
        share.publicPermission = .none
        _ = try await db.modifyRecords(saving: [root, share], deleting: [])
        return (share, c)
    }

    func accept(_ metadata: CKShare.Metadata) async {
        ensureEngines()
        do {
            _ = try await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)
            try await sharedEngine?.fetchChanges()
            status = "Joined a shared trip"
        } catch {
            status = "Couldn't join the shared trip: \(error.localizedDescription)"
        }
    }

    // MARK: Engine events

    fileprivate func handle(_ event: CKSyncEngine.Event, scope: CKDatabase.Scope) {
        switch event {
        case .stateUpdate(let e):
            if scope == .private { state.privateEngine = e.stateSerialization } else { state.sharedEngine = e.stateSerialization }
            saveState()
        case .accountChange(let e):
            switch e.changeType {
            case .signIn: status = "Signed in to iCloud"
            case .signOut, .switchAccounts: status = "iCloud account changed — sync paused. Your trips on this device are untouched."
            @unknown default: break
            }
        case .fetchedDatabaseChanges(let e):
            for deletion in e.deletions { zoneGone(deletion.zoneID) }
        case .fetchedRecordZoneChanges(let e):
            applyFetched(records: e.modifications.map(\.record), deletions: e.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let e):
            handleSent(e, scope: scope)
        case .didFetchChanges:
            finishFetch()
        default: break
        }
    }

    private func zoneGone(_ zone: CKRecordZone.ID) {
        guard let context, let id = CloudRecords.tripID(zone: zone), let trip = CloudApply.trip(id: id, in: context) else { return }
        trip.cloudSync = false
        state.fingerprints[id.uuidString] = nil
        status = "“\(trip.name)” is no longer shared. Your copy on this device is kept."
        saveState()
    }

    private func applyFetched(records: [CKRecord], deletions: [CKRecord.ID]) {
        guard let context else { return }
        let ordered = records.sorted { rank($0.recordType) < rank($1.recordType) }
        var touched: [UUID: Set<String>] = [:]

        for record in ordered {
            guard let (type, _) = CloudRecords.parse(record.recordID.recordName),
                  let tripID = CloudRecords.tripID(zone: record.recordID.zoneID) else { continue }   // e.g. the CKShare record
            let key = tripID.uuidString
            guard !state.tombstones.contains(key) else { continue }
            let name = record.recordID.recordName
            state.systemFields[name] = CloudRecords.archiveSystemFields(record)

            let owner = record.recordID.zoneID.ownerName == CKCurrentUserDefaultName ? "" : record.recordID.zoneID.ownerName
            var trip = CloudApply.trip(id: tripID, in: context)
            if trip == nil, type == .trip, let h = CloudRecords.header(from: record) {
                trip = CloudApply.applyHeader(h, owner: owner, context: context)   // a share just arrived
            }
            guard let trip, trip.cloudSync else { continue }

            // A newer unsent local edit wins; ours will overwrite the server copy on the next send.
            if hasUnsentLocalEdit(name, tripKey: key, trip: trip),
               CloudRecords.resolve(localEditedAt: state.lastEdited[name], serverEditedAt: CloudRecords.editedAt(record)) == .local { continue }

            switch type {
            case .trip: if let h = CloudRecords.header(from: record) { CloudApply.applyHeader(h, owner: owner, context: context) }
            case .traveler: if let t = CloudRecords.traveler(from: record) { CloudApply.upsert(t, into: trip, context: context) }
            case .day: if let d = CloudRecords.day(from: record) { CloudApply.upsert(d, into: trip, context: context) }
            case .check: if let c = CloudRecords.check(from: record) { CloudApply.upsert(c, into: trip, context: context) }
            case .item:
                if let i = CloudRecords.item(from: record) {
                    linkHints[i.id] = (i.dayID, i.attendeeIDs)
                    CloudApply.upsert(i, into: trip, context: context)
                }
            }
            state.lastEdited[name] = CloudRecords.editedAt(record) ?? state.lastEdited[name]
            touched[tripID, default: []].insert(name)
        }

        for recordID in deletions {
            guard let (type, id) = CloudRecords.parse(recordID.recordName),
                  let tripID = CloudRecords.tripID(zone: recordID.zoneID),
                  let trip = CloudApply.trip(id: tripID, in: context), trip.cloudSync else { continue }
            CloudApply.remove(type, id: id, from: trip, context: context)
            state.fingerprints[tripID.uuidString]?[recordID.recordName] = nil
            state.systemFields[recordID.recordName] = nil
        }

        // Record what we just applied as "in sync" so it isn't sent straight back.
        try? context.save()
        for (tripID, names) in touched {
            guard let trip = CloudApply.trip(id: tripID, in: context) else { continue }
            let now = Dictionary(uniqueKeysWithValues: CloudRecords.localRecords(TripSnapshot(trip: trip)).map { ($0.name, $0.fingerprint) })
            for n in names { state.fingerprints[tripID.uuidString, default: [:]][n] = now[n] }
        }
        saveState()
    }

    private func hasUnsentLocalEdit(_ name: String, tripKey: String, trip: Trip) -> Bool {
        guard let synced = state.fingerprints[tripKey]?[name] else { return false }
        let current = CloudRecords.localRecords(TripSnapshot(trip: trip)).first { $0.name == name }?.fingerprint
        return current != nil && current != synced
    }

    private func rank(_ recordType: String) -> Int {
        switch recordType {
        case "Trip": 0; case "Traveler": 1; case "Day": 2; case "Item": 3; default: 4
        }
    }

    private func finishFetch() {
        guard let context else { return }
        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter(\.cloudSync)
        for trip in trips { CloudApply.relinkOrphans(trip, links: linkHints, context: context) }
        try? context.save()
        linkHints.removeAll()
        status = ""
    }

    private func handleSent(_ e: CKSyncEngine.Event.SentRecordZoneChanges, scope: CKDatabase.Scope) {
        let engine = scope == .private ? privateEngine : sharedEngine
        for record in e.savedRecords {
            let name = record.recordID.recordName
            guard let tripID = CloudRecords.tripID(zone: record.recordID.zoneID) else { continue }
            state.systemFields[name] = CloudRecords.archiveSystemFields(record)
            if let fp = sending[name] { state.fingerprints[tripID.uuidString, default: [:]][name] = fp }
            sending[name] = nil
            queuedSaves[name] = nil
        }
        for id in e.deletedRecordIDs {
            if let tripID = CloudRecords.tripID(zone: id.zoneID) { state.fingerprints[tripID.uuidString]?[id.recordName] = nil }
            state.systemFields[id.recordName] = nil
            queuedDeletes.remove(id.recordName)
        }
        for (id, error) in e.failedRecordDeletes where error.code == .unknownItem {
            queuedDeletes.remove(id.recordName)
            if let tripID = CloudRecords.tripID(zone: id.zoneID) { state.fingerprints[tripID.uuidString]?[id.recordName] = nil }
        }
        for failure in e.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                state.systemFields[id.recordName] = CloudRecords.archiveSystemFields(server)
                if CloudRecords.resolve(localEditedAt: state.lastEdited[id.recordName], serverEditedAt: CloudRecords.editedAt(server)) == .local {
                    engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])           // resend on top of the new change tag
                } else {
                    engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                    queuedSaves[id.recordName] = nil
                    if let tripID = CloudRecords.tripID(zone: id.zoneID) { state.fingerprints[tripID.uuidString]?[id.recordName] = nil }
                    state.lastEdited[id.recordName] = nil
                    applyFetched(records: [server], deletions: [])
                }
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .unknownItem:
                state.systemFields[id.recordName] = nil                                      // it was deleted remotely; recreate
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy, .requestRateLimited, .notAuthenticated:
                break                                                                        // the engine retries these itself
            default:
                status = "Sync problem: \(failure.error.localizedDescription)"
            }
        }
        saveState()
    }

    // MARK: Outgoing batch

    fileprivate func nextBatch(_ options: CKSyncEngine.SendChangesContext, scope: CKDatabase.Scope) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let engine = scope == .private ? privateEngine : sharedEngine else { return nil }
        let pending = engine.state.pendingRecordZoneChanges.filter { options.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await MainActor.run { self.buildRecord(recordID, engine: engine) }
        }
    }

    private func buildRecord(_ recordID: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
        let name = recordID.recordName
        guard let context, let tripID = CloudRecords.tripID(zone: recordID.zoneID),
              let trip = CloudApply.trip(id: tripID, in: context), trip.cloudSync else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        let snapshot = TripSnapshot(trip: trip)
        let base = state.systemFields[name].flatMap(CloudRecords.record(fromSystemFields:))
        guard let record = CloudRecords.makeRecord(named: name, from: snapshot, zone: recordID.zoneID, base: base,
                                                   editedAt: state.lastEdited[name] ?? .now) else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])   // deleted locally since it was queued
            return nil
        }
        sending[name] = CloudRecords.localRecords(snapshot).first { $0.name == name }?.fingerprint
        return record
    }

    // MARK: Persistence

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cloudsync.json")
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL), let s = try? JSONDecoder().decode(CloudSyncState.self, from: data) else { return }
        state = s
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }
}

/// CKSyncEngine wants a Sendable delegate; this forwards to the main-actor CloudSync.
private final class EngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    let scope: CKDatabase.Scope
    weak var owner: CloudSync?
    init(scope: CKDatabase.Scope, owner: CloudSync) { self.scope = scope; self.owner = owner }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { owner?.handle(event, scope: scope) }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await owner?.nextBatch(context, scope: scope)
    }
}
