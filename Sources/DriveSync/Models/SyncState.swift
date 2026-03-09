import SwiftUI

enum SyncState: String, CaseIterable {
    case idle
    case syncing
    case uptodate
    case paused
    case warning
    case error

    var label: String {
        switch self {
        case .idle: "Idle"
        case .syncing: "Syncing..."
        case .uptodate: "Up-to-date"
        case .paused: "Paused"
        case .warning: "Setup Required"
        case .error: "Error"
        }
    }

    var sfSymbol: String {
        switch self {
        case .idle: "moon.zzz.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .uptodate: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    var iconName: String {
        switch self {
        case .idle: "icon_idle"
        case .syncing: "icon_syncing"
        case .uptodate: "icon_uptodate"
        case .paused: "icon_paused"
        case .warning: "icon_warning"
        case .error: "icon_error"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .syncing: .blue
        case .uptodate: .green
        case .paused: .orange
        case .warning: .yellow
        case .error: .red
        }
    }
}

struct DriveDisplayInfo: Identifiable, Sendable {
    let id: String           // volume UUID
    let label: String
    let volumeName: String?
    let filesystem: String?
    let capacity: Int64?
    let mountPoint: String?
    let registeredAt: Date
    let lastSyncAt: Date?
    let isConnected: Bool

    var capacityText: String? {
        guard let capacity else { return nil }
        return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
    }

    var lastSyncText: String {
        guard let lastSyncAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    var shortUUID: String {
        String(id.prefix(8))
    }

    /// Join registered drive + optional live mount data
    static func from(registered: RegisteredDrive, mount: ExternalDrive?) -> DriveDisplayInfo {
        DriveDisplayInfo(
            id: registered.id,
            label: registered.label,
            volumeName: mount?.name,
            filesystem: mount?.filesystem,
            capacity: mount?.capacity,
            mountPoint: mount?.mountPoint,
            registeredAt: registered.registeredAt,
            lastSyncAt: registered.lastSyncAt,
            isConnected: mount != nil
        )
    }
}
