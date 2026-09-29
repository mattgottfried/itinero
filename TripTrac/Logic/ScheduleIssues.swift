import Foundation

struct ScheduleIssue: Identifiable, Equatable {
    enum Kind: Equatable { case overlap, missingCheckout, endsBeforeStart }
    let kind: Kind
    let itemIDs: [UUID]
    let message: String
    var id: String { "\(kind)-" + itemIDs.map(\.uuidString).sorted().joined(separator: "-") }
}

enum ScheduleIssues {
    /// Overlaps only count between items that share at least one traveler (empty attendees = the whole group).
    static func detect<T: Schedulable>(_ items: [T], allTravelerIDs: Set<UUID>) -> [ScheduleIssue] {
        var issues: [ScheduleIssue] = []
        let active = items.filter { $0.status != .cancelled && $0.status != .idea }

        for item in active {
            if item.category == .stay, item.status == .booked, item.endsAt == nil {
                issues.append(ScheduleIssue(kind: .missingCheckout, itemIDs: [item.id],
                                            message: "“\(item.title)” is booked but has no check-out date"))
            }
            if let s = item.startsAt, let e = item.endsAt, e < s {
                issues.append(ScheduleIssue(kind: .endsBeforeStart, itemIDs: [item.id],
                                            message: "“\(item.title)” ends before it starts"))
            }
        }

        let timed = active.filter { $0.category != .stay && $0.startsAt != nil }
        for i in timed.indices {
            for j in timed.indices where j > i {
                let a = timed[i], b = timed[j]
                guard let aStart = a.startsAt, let bStart = b.startsAt else { continue }
                let aEnd = max(a.endsAt ?? aStart, aStart), bEnd = max(b.endsAt ?? bStart, bStart)
                guard aStart < bEnd, bStart < aEnd else { continue }
                guard sharesTraveler(a, b, all: allTravelerIDs) else { continue }
                issues.append(ScheduleIssue(kind: .overlap, itemIDs: [a.id, b.id],
                                            message: "“\(a.title)” overlaps “\(b.title)”"))
            }
        }
        return issues
    }

    static func sharesTraveler(_ a: some Schedulable, _ b: some Schedulable, all: Set<UUID>) -> Bool {
        let sa = a.attendeeIDs.isEmpty ? all : Set(a.attendeeIDs)
        let sb = b.attendeeIDs.isEmpty ? all : Set(b.attendeeIDs)
        if sa.isEmpty && sb.isEmpty { return true }   // no roster: everything is the same group
        return !sa.isDisjoint(with: sb)
    }
}
