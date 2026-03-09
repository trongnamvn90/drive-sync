import SwiftUI

struct RegisterDriveSheet: View {
    @Binding var isPresented: Bool
    var appState: AppState

    @State private var availableDrives: [ExternalDrive] = []
    @State private var selectedDriveId: String?
    @State private var label = ""
    @State private var loading = true
    @State private var registering = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Register New Drive")
                .font(.headline)
                .padding()

            Divider()

            if loading {
                ProgressView("Scanning drives...")
                    .padding(40)
            } else if availableDrives.isEmpty {
                emptyState
            } else {
                driveList
            }

            Divider()

            // Buttons
            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Register") { registerDrive() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedDriveId == nil || label.isEmpty || registering)
            }
            .padding()
        }
        .frame(width: 440)
        .task { await loadAvailableDrives() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No external drives found")
                .font(.headline)
            Text("Plug in a drive and try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    @ViewBuilder
    private var driveList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select drive:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(availableDrives) { drive in
                HStack {
                    Image(systemName: selectedDriveId == drive.id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selectedDriveId == drive.id ? .blue : .secondary)
                    Image(systemName: "internaldrive")
                    VStack(alignment: .leading) {
                        Text("\(drive.name) • \(drive.filesystem) • \(drive.capacityText)")
                            .font(.system(.body, design: .monospaced))
                        Text("UUID: \(drive.id.prefix(8))...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedDriveId = drive.id }
            }

            LabeledContent("Label:") {
                TextField("My Drive", text: $label)
                    .frame(width: 200)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func loadAvailableDrives() async {
        let connected = MountDetector.shared.connectedDrives
        let registered = await DriveRegistry.shared.all()
        let registeredIds = Set(registered.map(\.id))

        availableDrives = connected.filter { !registeredIds.contains($0.id) }
        loading = false
    }

    private func registerDrive() {
        guard let driveId = selectedDriveId else { return }
        registering = true
        errorMessage = nil

        Task {
            do {
                _ = try await DriveRegistry.shared.register(volumeId: driveId, label: label)
                await appState.refreshDriveList()
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
                registering = false
            }
        }
    }
}
