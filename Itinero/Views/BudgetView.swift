import SwiftUI
import SwiftData

struct BudgetView: View {
    let trip: Trip
    @State private var openItem: ItineraryItem?

    private var totals: [CurrencyTotals] { BudgetLogic.totals(trip.allItems, travelerIDs: trip.allTravelers.map(\.id)) }
    private var costed: [ItineraryItem] {
        trip.allItems.filter { ($0.cost ?? 0) > 0 && $0.status != .cancelled }.sorted { ($0.cost ?? 0) > ($1.cost ?? 0) }
    }
    private var missing: Int { BudgetLogic.itemsWithoutCost(trip.allItems) }

    var body: some View {
        let totals = self.totals
        Group {
            if totals.isEmpty {
                ContentUnavailableView {
                    Label("No costs yet", systemImage: "creditcard")
                } description: {
                    Text("Add a cost when you edit a flight, stay or booking and it will be totaled here, split by traveler.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(totals, id: \.currency) { t in
                            SectionCard(title: t.currency.isEmpty ? "No currency set" : "Budget · \(t.currency)", systemImage: "creditcard.fill", tone: .money) {
                                HStack(spacing: 8) {
                                    StatChip(value: BudgetLogic.format(t.planned, currency: t.currency), label: "planned", tone: .money)
                                    StatChip(value: BudgetLogic.format(t.paid, currency: t.currency), label: "paid", tone: .good)
                                    StatChip(value: BudgetLogic.format(t.remaining, currency: t.currency), label: "to pay", tone: t.remaining > 0 ? .caution : .good)
                                }
                                if !t.perTraveler.isEmpty {
                                    Divider()
                                    Text("Split by traveler").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ForEach(trip.allTravelers.filter { t.perTraveler[$0.id] != nil }) { person in
                                        HStack {
                                            Text(person.name).font(.subheadline)
                                            Spacer()
                                            Text(BudgetLogic.format(t.perTraveler[person.id] ?? 0, currency: t.currency))
                                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }
                        if missing > 0 {
                            Label("\(missing) flight, stay or ticket item\(missing == 1 ? " has" : "s have") no cost yet", systemImage: "exclamationmark.circle")
                                .font(.caption.weight(.semibold)).foregroundStyle(StatusTone.caution.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        SectionCard(title: "Costs", systemImage: "list.bullet", tone: .money) {
                            ForEach(costed) { item in
                                Button { openItem = item } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                                            if item.isPaid { Label("Paid", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(StatusTone.good.color) }
                                        }
                                        Spacer()
                                        Text(BudgetLogic.format(item.cost ?? 0, currency: item.currency)).font(.subheadline.monospacedDigit().weight(.semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityHint("Open details")
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openItem) { ItemDetailView(item: $0, trip: trip) }
    }
}
