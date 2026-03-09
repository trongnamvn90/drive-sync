import SwiftUI

struct GoogleDriveTab: View {
    @Bindable var appState: AppState
    @State private var showDisconnectConfirm = false

    var body: some View {
        Form {
            switch appState.googleState {
            case .connected:
                connectedView
            case .connecting:
                connectingView
            case .disconnected:
                disconnectedView
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedView: some View {
        if let account = appState.googleAccount {
            Section {
                LabeledContent("Status") {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                LabeledContent("Account", value: account.email)
                LabeledContent("Storage") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(account.storageUsedText) / \(account.storageTotalText)")
                        ProgressView(value: account.storageFraction)
                            .frame(width: 140)
                            .tint(account.storageFraction > 0.9 ? .red : .blue)
                    }
                }
                LabeledContent("Folder") {
                    Picker("", selection: $appState.googleFolder) {
                        ForEach(appState.googleFolders) { folder in
                            Text(folder.name).tag(folder.name)
                        }
                    }
                    .frame(width: 180)
                }
            }

            Section {
                HStack {
                    Button { appState.reloginGoogle() } label: {
                        Label("Re-login", systemImage: "arrow.counterclockwise")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
            .alert("Disconnect Google Drive?", isPresented: $showDisconnectConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    appState.disconnectGoogle()
                }
            } message: {
                Text("Token will be revoked. You'll need to re-connect to sync.")
            }

            Section("Bandwidth") {
                LabeledContent("Upload") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Stepper(value: $appState.uploadLimit, in: 0...10000, step: 100) {
                            HStack {
                                TextField("", value: $appState.uploadLimit, format: .number)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("KB/s")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("0 = unlimited")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                LabeledContent("Download") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Stepper(value: $appState.downloadLimit, in: 0...10000, step: 100) {
                            HStack {
                                TextField("", value: $appState.downloadLimit, format: .number)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("KB/s")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("0 = unlimited")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Connecting

    @ViewBuilder
    private var connectingView: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for Google...")
                        .foregroundStyle(.secondary)
                }
            }

            Text("A browser window should have opened.\nSign in with your Google account to continue.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                appState.cancelConnect()
            }
        }

        errorBanner
    }

    // MARK: - Disconnected

    @ViewBuilder
    private var disconnectedView: some View {
        Section {
            LabeledContent("Status") {
                Label("Not connected", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }

        errorBanner

        Section {
            VStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("Connect your Google Drive to start syncing files between your external drives and the cloud.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button { appState.connectGoogle() } label: {
                    Label("Connect Google Drive", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appState.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }
}
