import SwiftUI

/// The itinerary row used by the timeline, search, the booking tracker and issues.
struct ItemRow: View {
    let item: ItineraryItem
    let trip: Trip
    var hasIssue = false
    var showDate = false

    static func zone(for item: ItineraryItem, trip: Trip) -> TimeZone {
        item.timeZoneID.isEmpty ? trip.timeZone : (TimeZone(identifier: item.timeZoneID) ?? trip.timeZone)
    }

    /// "6:15 AM – 8:00 AM", plus the zone abbreviation when it isn't the trip's own zone.
    private func timeString(_ tz: TimeZone) -> String {
        let text = Fmt.timeText(start: item.startsAt, end: item.endsAt, note: item.timeNote, in: tz)
        guard let s = item.startsAt, tz.identifier != trip.timeZone.identifier else { return text }
        return text + " " + TimeDisplay.zoneAbbreviation(tz, at: s)
    }

    var body: some View {
        let tz = Self.zone(for: item, trip: trip)
        let days = item.startsAt.map { TripLogic.daysUntil($0) }
        let baseTone = statusTone(for: item.status, daysUntil: days)
        let tone: StatusTone = item.isDone ? .good : baseTone
        let time = timeString(tz)
        let yours = item.startsAt.flatMap { TimeDisplay.yourTime(for: $0, itemZone: tz, yourZone: .current) }
        let who = item.allAttendees.isEmpty ? "" : item.allAttendees.map(\.name).sorted().joined(separator: ", ")
        let checkout = item.category == .stay ? item.endsAt.map { "Check-out \(Fmt.shortDate($0, in: tz))" } : nil
        let dateText = showDate ? (item.day.map { Fmt.dayHeader($0.date, in: trip.timeZone).capitalized } ?? "") : ""
        let statusLabel = item.isDone ? "Done" : item.status.label
        let statusSymbol = item.isDone ? "checkmark.circle.fill" : item.status.symbol

        ListRowCard(
            tone: tone, tile: .symbol(item.category.symbol),
            title: item.title,
            subtitle: statusLabel, subtitleSymbol: statusSymbol, subtitleTone: tone,
            dimmed: item.isDone || item.status == .cancelled,
            accessibilityValue: [item.category.label, statusLabel, dateText, time, yours.map { "your time \($0)" } ?? "", item.place,
                                 who.isEmpty ? "whole group" : who, item.isOptional ? "optional" : "",
                                 hasIssue ? "has a schedule issue" : ""]
                .filter { !$0.isEmpty }.joined(separator: ", "),
            accessibilityHint: "Open details"
        ) {
            VStack(alignment: .leading, spacing: 3) {
                let line = [dateText, time, checkout ?? "", item.place].filter { !$0.isEmpty }.joined(separator: " · ")
                if !line.isEmpty { Text(line).lineLimit(2) }
                if let yours { Label("\(yours) your time", systemImage: "clock.arrow.2.circlepath").lineLimit(1) }
                HStack(spacing: 6) {
                    if let aboard = item.allAboardAt, !item.isDone {
                        BadgePill(text: "All aboard \(Fmt.time(aboard, in: tz))", systemImage: "ferry.fill",
                                  tone: PortLogic.allAboardTone(aboard, now: .now), solid: true)
                    }
                    if hasIssue { BadgePill(text: "Check schedule", systemImage: "exclamationmark.triangle.fill", tone: .caution) }
                    if item.isOptional { BadgePill(text: "Optional", systemImage: "questionmark.circle", tone: .neutral) }
                    if item.isMustDo { BadgePill(text: "Must do", systemImage: "star.fill", tone: .star) }
                }
                HStack(spacing: 6) {
                    if !who.isEmpty { Label(who, systemImage: "person.2.fill").lineLimit(1) }
                    if !item.confirmation.isEmpty { Label(item.confirmation, systemImage: "number").lineLimit(1) }
                }
            }
        }
    }
}
