import SwiftUI
import SwiftData

struct ChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    @State private var newTitle = ""
    @State private var newGroup = "To do"
    @State private var newOwner: UUID?
    @State private var filterOwner: UUID?
    @State private var undo: (title: String, group: String, owner: UUID?, done: Bool)?
    @FocusState private var adding: Bool

    private static let defaultGroups = ["To do", "Packing", "Documents"]

    private var groups: [String] {
        var seen = Self.defaultGroups
        for g in trip.allChecklist.map(\.group) where !seen.contains(g) { seen.append(g) }
        return seen
    }
    private var visible: [ChecklistItem] {
        trip.allChecklist.filter { filterOwner == nil || $0.owner == nil || $0.owner?.id == filterOwner }
    }
    private var progress: (done: Int, total: Int) { (visible.filter(\.isDone).count, visible.count) }

    var body: some View {
        List {
            if progress.total > 0 {
                Section {
                    HStack {
                        StatChip(value: "\(progress.done)/\(progress.total)", label: "done", tone: progress.done == progress.total ? .good : .info)
                        StatChip(value: "\(progress.total - progress.done)", label: "to go", tone: progress.done == progress.total ? .good : .caution)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            Section("ADD") {
                TextField("Add an item", text: $newTitle).focused($adding).submitLabel(.done).onSubmit(add)
                Picker("List", selection: $newGroup) { ForEach(groups, id: \.self) { Text($0).tag($0) } }
                if !trip.allTravelers.isEmpty {
                    Picker("For", selection: $newOwner) {
                        Text("Everyone").tag(UUID?.none)
                        ForEach(trip.allTravelers) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Button("Add", systemImage: "plus.circle.fill", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(groups, id: \.self) { g in
                let rows = visible.filter { $0.group == g }.sorted { ($0.isDone ? 1 : 0, $0.sortOrder) < ($1.isDone ? 1 : 0, $1.sortOrder) }
                if !rows.isEmpty {
                    Section(g.uppercased()) {
                        ForEach(rows) { item in
                            Button { item.isDone.toggle() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isDone ? StatusTone.good.color : Color.secondary).font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).strikethrough(item.isDone).foregroundStyle(item.isDone ? .secondary : .primary)
                                        if let owner = item.owner { Label(owner.name, systemImage: "person.fill").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.title)
                            .accessibilityValue([item.isDone ? "done" : "not done", item.owner.map { "for \($0.name)" } ?? "for everyone"].joined(separator: ", "))
                            .accessibilityHint("Toggles done")
                            .accessibilityAddTraits(.isButton)
                            .swipeActions { Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") } }
                        }
                    }
                }
            }
            if trip.allChecklist.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No checklist yet", systemImage: "checklist")
                    } description: { Text("Add packing items, documents to sort out, or anything you don't want to forget.") }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: progress.done)
        .navigationTitle("Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !trip.allTravelers.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filterOwner) {
                            Text("Everyone's").tag(UUID?.none)
                            ForEach(trip.allTravelers) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } label: { Image(systemName: filterOwner == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                        .accessibilityLabel("Filter checklist by traveler")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo {
                UndoToast(message: "Deleted “\(undo.title)”") { restore() }.padding(.bottom, 12)
            }
        }
        .animation(.easeInOut, value: undo?.title)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let item = ChecklistItem(title: title, group: newGroup)
        item.sortOrder = (trip.allChecklist.map(\.sortOrder).max() ?? 0) + 1
        item.trip = trip
        item.owner = trip.allTravelers.first { $0.id == newOwner }
        modelContext.insert(item)
        newTitle = ""
        adding = true
    }

    private func delete(_ item: ChecklistItem) {
        undo = (item.title, item.group, item.owner?.id, item.isDone)
        modelContext.delete(item)
        let title = item.title
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo?.title == title { undo = nil }
        }
    }

    private func restore() {
        guard let u = undo else { return }
        let item = ChecklistItem(title: u.title, group: u.group)
        item.isDone = u.done
        item.trip = trip
        item.owner = trip.allTravelers.first { $0.id == u.owner }
        item.sortOrder = (trip.allChecklist.map(\.sortOrder).max() ?? 0) + 1
        modelContext.insert(item)
        undo = nil
    }
}
