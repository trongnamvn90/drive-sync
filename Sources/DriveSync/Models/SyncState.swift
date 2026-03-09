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

struct DriveInfo: Identifiable {
    let id = UUID()
    var label: String
    var volumeName: String
    var uuid: String
    var filesystem: String
    var capacity: String
    var lastSync: String
    var isConnected: Bool
}
