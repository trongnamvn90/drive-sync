import SwiftUI

struct RegisterDriveSheet: View {
    @Binding var isPresented: Bool
    @State private var selectedDrive = 1
    @State private var label = ""
    @State private var formatDrive = false
    @State private var volumeName = ""
    @State private var filesystem = "exFAT"
    @State private var syncMethod = "Merge both"

    private let mockDrives = [
        (name: "ZORRO", fs: "exFAT", size: "500GB", uuid: "A1B2C3D4"),
        (name: "BACKUP", fs: "APFS", size: "1TB", uuid: "X9Y8Z7W6"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Register New Drive")
                .font(.headline)
                .padding()

            Divider()

            // Drive selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select drive:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(0..<mockDrives.count, id: \.self) { idx in
                    let drive = mockDrives[idx]
                    HStack {
                        Image(systemName: selectedDrive == idx ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedDrive == idx ? .blue : .secondary)
                        Image(systemName: "internaldrive")
                        VStack(alignment: .leading) {
                            Text("\(drive.name) • \(drive.fs) • \(drive.size)")
                                .font(.system(.body, design: .monospaced))
                            Text("UUID: \(drive.uuid)...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDrive = idx }
                }

                LabeledContent("Label:") {
                    TextField("My Drive", text: $label)
                        .frame(width: 200)
                }

                Toggle("Format drive before registering", isOn: $formatDrive)

                if formatDrive {
                    GroupBox {
                        LabeledContent("Volume name:") {
                            TextField("ZORRO", text: $volumeName)
                                .frame(width: 150)
                        }
                        LabeledContent("Filesystem:") {
                            Picker("", selection: $filesystem) {
                                Text("exFAT (cross-platform)").tag("exFAT")
                                Text("APFS (macOS only)").tag("APFS")
                            }
                            .frame(width: 200)
                        }
                    }
                }
            }
            .padding()

            // Warnings area
            Divider()
            warningsArea
                .padding()

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Register") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440)
    }

    @ViewBuilder
    private var warningsArea: some View {
        if formatDrive {
            Label("ALL DATA ON DRIVE WILL BE ERASED!", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout.bold())
        } else if selectedDrive == 0 {
            // Simulate: UUID already registered
            VStack(alignment: .leading, spacing: 4) {
                Label("UUID matches registered \"Home Drive\"", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Format drive to generate new UUID, or remove old drive in Drives tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Cloud has 12GB → will pull to drive", systemImage: "info.circle")
                .foregroundStyle(.blue)
        }
    }
}
