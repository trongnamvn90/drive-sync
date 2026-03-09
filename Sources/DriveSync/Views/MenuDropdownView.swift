import SwiftUI

struct MenuDropdownView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if appState.googleState != .connected || appState.drives.isEmpty {
            warningHeader
        } else if appState.currentState == .syncing {
            syncingHeader
        } else {
            normalHeader
        }

        Divider()

        Button { } label: {
            Label("Open Folder", systemImage: "folder")
        }
        .keyboardShortcut("o")
        .disabled(appState.googleState != .connected)

        Divider()

        Button("Sync Now") {}
            .keyboardShortcut("s")
            .disabled(appState.googleState != .connected)

        if appState.currentState == .paused {
            Button("Resume Sync") {}
                .disabled(appState.googleState != .connected)
        } else {
            Button("Pause Sync") {}
                .disabled(appState.googleState != .connected)
        }

        Divider()

        Button("Safe Eject") {}
            .keyboardShortcut("e")

        Divider()

        Button("Drives...") {
            openSettingsWindow()
        }

        Button("Settings...") {
            openSettingsWindow()
        }
        .keyboardShortcut(",")

        Button("View Logs") {
            openSettingsWindow()
        }

        Divider()

        Button("About DriveSync") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "about")
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Button("Quit DriveSync") {
            appState.stopIconCycling()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Headers

    @ViewBuilder
    private var normalHeader: some View {
        Label(appState.currentState.label, systemImage: appState.currentState.sfSymbol)
            .font(.headline)
        if let drive = appState.drives.first(where: { $0.isConnected }) {
            Text("\(drive.label) • Synced \(drive.lastSyncText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var syncingHeader: some View {
        Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
            .font(.headline)
        Text("Home Drive • \(appState.syncFilesDone)/\(appState.syncFilesTotal) files • \(Int(appState.syncProgress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
        ProgressView(value: appState.syncProgress)
        Text("\(appState.syncBytesDone)/\(appState.syncBytesTotal)")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var warningHeader: some View {
        Label("Setup Required", systemImage: "exclamationmark.triangle.fill")
            .font(.headline)

        Divider()

        if appState.googleState != .connected {
            Button {
                openSettingsWindow()
            } label: {
                Label(
                    appState.googleState == .connecting
                        ? "Google Drive connecting..."
                        : "Google Drive not connected",
                    systemImage: appState.googleState == .connecting
                        ? "arrow.triangle.2.circlepath"
                        : "xmark.circle"
                )
            }
        }

        if appState.drives.isEmpty {
            Button {
                openSettingsWindow()
            } label: {
                Label("No drives registered", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Helpers

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
