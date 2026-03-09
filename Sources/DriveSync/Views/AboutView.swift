import SwiftUI

struct AboutView: View {
    @State private var showLicenses = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // App icon
            if let url = Bundle.module.url(forResource: "app_icon", withExtension: "jpg"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 4, y: 2)
            } else {
                Image(systemName: "externaldrive.fill.badge.icloud")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
            }

            Text("DriveSync")
                .font(.title.bold())

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 180)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("rclone:")
                        .foregroundStyle(.secondary)
                    Text("v1.68.0")
                }
                HStack(spacing: 4) {
                    Text("macOS:")
                        .foregroundStyle(.secondary)
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                }
            }
            .font(.caption)

            Divider()
                .frame(width: 180)

            Text("© 2026 Zorro")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("github.com/zorro/drive-sync",
                 destination: URL(string: "https://github.com/zorro/drive-sync")!)
                .font(.caption)

            Button("Licenses") {
                showLicenses = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
        .padding()
        .frame(width: 300, height: 380)
        .sheet(isPresented: $showLicenses) {
            LicensesView(isPresented: $showLicenses)
        }
    }
}

struct LicensesView: View {
    @Binding var isPresented: Bool

    private let licenses = [
        ("rclone", "MIT License", "https://github.com/rclone/rclone"),
        ("SwiftUI", "Apple EULA", "https://developer.apple.com"),
        ("TOMLDecoder", "MIT License", "https://github.com/dduan/TOMLDecoder"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Open Source Licenses")
                .font(.headline)
                .padding()

            Divider()

            List(licenses, id: \.0) { name, license, url in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                    Text(license)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(url, destination: URL(string: url)!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 380, height: 320)
    }
}
