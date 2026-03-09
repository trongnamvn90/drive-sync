import SwiftUI

struct DrivesTab: View {
    @Bindable var appState: AppState
    @State private var showRegisterSheet = false
    @State private var editingDriveId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appState.drives) { drive in
                        DriveCard(
                            drive: drive,
                            onEdit: { editingDriveId = drive.id },
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
            RegisterDriveSheet(isPresented: $showRegisterSheet)
        }
    }

    private func removeDrive(_ drive: DriveInfo) {
        appState.drives.removeAll { $0.id == drive.id }
    }
}

struct DriveCard: View {
    let drive: DriveInfo
    let onEdit: () -> Void
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
                    Text(drive.volumeName)
                    Text("•")
                    Text("UUID: \(drive.uuid)...")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(drive.filesystem)
                    Text("•")
                    Text(drive.capacity)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Last sync: \(drive.lastSync)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(spacing: 4) {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button { showRemoveConfirm = true } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
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
