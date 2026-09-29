import SwiftUI

struct IssuesView: View {
    let trip: Trip
    @State private var openItem: ItineraryItem?

    private var issues: [ScheduleIssue] {
        ScheduleIssues.detect(trip.allItems, allTravelerIDs: Set(trip.allTravelers.map(\.id)))
    }

    var body: some View {
        Group {
            if issues.isEmpty {
                ContentUnavailableView {
                    Label("No schedule issues", systemImage: "checkmark.circle.fill")
                } description: { Text("Nobody is double-booked and every booked stay has a check-out.") }
            } else {
                List {
                    Section {
                        ForEach(issues) { issue in
                            Button { openItem = trip.allItems.first { $0.id == issue.itemIDs.first } } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.message).font(.subheadline)
                                        Text(kindText(issue.kind)).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(StatusTone.caution.color)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Open the first item")
                        }
                    } footer: {
                        Text("Overlaps only count when the same traveler is on both items. Some overlaps are intentional — this is just a heads-up.")
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Schedule Issues")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openItem) { ItemDetailView(item: $0, trip: trip) }
    }

    private func kindText(_ k: ScheduleIssue.Kind) -> String {
        switch k {
        case .overlap: "Overlapping times"
        case .missingCheckout: "Missing check-out"
        case .endsBeforeStart: "End before start"
        }
    }
}
