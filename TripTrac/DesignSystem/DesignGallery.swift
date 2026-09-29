import SwiftUI

/// Preview-only catalogue of every design-system component, for eyeballing light/dark/AX5.
#Preview("Design gallery") {
    ScrollView {
        VStack(spacing: 16) {
            HeroCard(eyebrow: "Land trip · in 46 days", headline: "Japan family trip",
                     stats: [("calendar", "15", "days"), ("checkmark.seal.fill", "6", "booked"), ("exclamationmark.circle", "31", "to book")]) {
                Label("Tokyo · Hakone · Osaka · Kyoto", systemImage: "mappin.and.ellipse")
            }
            SectionCard(title: "Needs booking", systemImage: "exclamationmark.circle", tone: .alert) {
                HStack { StatChip(value: "31", label: "items", tone: .caution); StatChip(value: "9", label: "urgent", tone: .alert); StatChip(value: "¥0", label: "spent", tone: .money) }
                HStack { ForEach(BookingStatus.allCases) { BookingBadge(status: $0, daysUntil: 10) } }
            }
            ListRowCard(tone: .good, tile: .symbol("airplane"), title: "Delta 121 MSP → HND",
                        subtitle: "Booked", subtitleSymbol: "checkmark.seal.fill", subtitleTone: .good, featured: true,
                        accessibilityValue: "Booked", accessibilityHint: "Open item") { Text("Nov 14 · 10:40 AM · Conf HBJITY") }
            ListRowCard(tone: .alert, tile: .number("46", unit: "days"), title: "Tokyo Disneyland",
                        subtitle: "Needs booking", subtitleSymbol: "exclamationmark.circle", subtitleTone: .alert,
                        accessibilityValue: "Needs booking", accessibilityHint: "Open item") { Text("Nov 18 · 8:00 AM") }
            UndoToast(message: "Deleted “Ramen hopping”") {}
            EmptyStateSample()
        }.padding()
    }
    .background(Color(.systemGroupedBackground))
}

private struct EmptyStateSample: View {
    var body: some View {
        ContentUnavailableView {
            Label("No plans yet", systemImage: "calendar.badge.plus")
        } description: { Text("Add flights, stays and activities to build your itinerary.") }
        actions: { Button("Add to itinerary") {}.buttonStyle(.borderedProminent) }
    }
}
