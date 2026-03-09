import SwiftUI

struct DrivesTab: View {
    @Bindable var appState: AppState
    @State private var showRegisterSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appState.drives) { drive in
                        DriveCard(
                            drive: drive,
                            onRemove: { removeDrive(drive) }
                        )
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    showRegisterSheet = true
                } label: {
                    Label("Register New Drive", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .sheet(isPresented: $showRegisterSheet) {
            RegisterDriveSheet(isPresented: $showRegisterSheet, appState: appState)
        }
    }

    private func removeDrive(_ drive: DriveDisplayInfo) {
        Task {
            try? await DriveRegistry.shared.unregister(drive.id)
            await appState.refreshDriveList()
        }
    }
}

struct DriveCard: View {
    let drive: DriveDisplayInfo
    let onRemove: () -> Void
    @State private var showRemoveConfirm = false

    var body: some View {
        HStack(alignment: .top) {
            // Status dot
            Circle()
                .fill(drive.isConnected ? .green : .gray)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(drive.label)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let volumeName = drive.volumeName {
                        Text(volumeName)
                        Text("•")
                    }
                    Text("UUID: \(drive.shortUUID)...")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if drive.isConnected {
                    HStack(spacing: 8) {
                        if let fs = drive.filesystem { Text(fs) }
                        if let cap = drive.capacityText {
                            Text("•")
                            Text(cap)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("Last sync: \(drive.lastSyncText)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button { showRemoveConfirm = true } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Remove Drive", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { onRemove() }
        } message: {
            Text("Remove \"\(drive.label)\" from DriveSync?")
        }
    }
}
