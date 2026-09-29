import SwiftUI
import SwiftData
import CloudKit
import UIKit

struct FamilySharingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sync = CloudSync.shared
    @Bindable var trip: Trip
    @State private var busy = false
    @State private var error: String?
    @State private var pendingShare: (share: CKShare, container: CKContainer)?
    @State private var showingController = false

    private var isParticipant: Bool { !trip.cloudOwnerName.isEmpty }
    private var accountOK: Bool { sync.accountStatus == .available }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(trip.cloudSync ? (isParticipant ? "Shared with you" : "Syncing with iCloud") : "Only on this device",
                          systemImage: trip.cloudSync ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(trip.cloudSync ? StatusTone.good.color : Color.secondary)
                    if sync.accountStatus != nil, !accountOK {
                        Label("Sign in to iCloud in Settings to share trips.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(StatusTone.caution.color)
                    }
                    if !sync.status.isEmpty { Text(sync.status).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("STATUS") } footer: {
                    Text(isParticipant
                         ? "Changes you make sync to everyone on this trip, and theirs sync to you. If the owner stops sharing, your copy stays on this device."
                         : "Family members you invite see this trip and can edit it. The newest edit to an item wins if two people change it at once.")
                }

                if !isParticipant {
                    Section {
                        Button {
                            Task { await invite() }
                        } label: {
                            Label(trip.cloudSync ? "Invite or manage people" : "Turn on & invite family", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(busy || !accountOK)
                        if busy { ProgressView() }
                    } footer: {
                        Text("Everyone needs an iCloud account and Itinero installed (TestFlight). Send the invite link from the share sheet.")
                    }
                }

                if trip.cloudSync {
                    Section {
                        Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { Task { await sync.syncNow() } }
                        Button(isParticipant ? "Stop syncing (keep my copy)" : "Stop syncing this trip", role: .destructive) {
                            sync.disable(trip)
                        }
                    } footer: {
                        Text("Stopping only affects this device. Nothing is deleted here or in iCloud.")
                    }
                }
                if let error { Section { Text(error).font(.caption).foregroundStyle(StatusTone.bad.color) } }
            }
            .navigationTitle("Family Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await sync.refreshAccountStatus() }
            .sheet(isPresented: $showingController) {
                if let pendingShare { CloudSharingView(share: pendingShare.share, container: pendingShare.container, title: trip.name) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func invite() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            pendingShare = try await sync.prepareShare(for: trip)
            showingController = true
        } catch {
            self.error = "Couldn't start sharing: \(error.localizedDescription)"
        }
    }
}

/// Apple's own invite/manage-people screen.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(title: title) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let c = UICloudSharingController(share: share, container: container)
        c.delegate = context.coordinator
        c.availablePermissions = [.allowReadWrite, .allowPrivate]
        return c
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }
        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
    }
}

// MARK: - Accepting an invite link

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in await CloudSync.shared.accept(cloudKitShareMetadata) }
    }
}
