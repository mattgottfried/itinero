import SwiftUI

struct ImportReportView: View {
    let report: ImportReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        StatChip(value: "\(report.itemCount)", label: "items imported", tone: .good)
                        StatChip(value: "\(report.warnings.count)", label: "to review", tone: report.warnings.isEmpty ? .good : .caution)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if !report.warnings.isEmpty {
                    Section {
                        ForEach(report.warnings) { w in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.item).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Label(w.message, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(StatusTone.caution.color)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: { Text("THINGS TO CHECK") } footer: {
                        Text("These were imported as written or left blank — nothing was guessed. Fix them from the itinerary.")
                    }
                }
            }
            .navigationTitle("Imported “\(report.tripName)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
