import SwiftUI

enum SettingsTab: String, CaseIterable {
    case googleDrive = "Google Drive"
    case drives = "Drives"
    case sync = "Sync"
    case app = "App"

    var icon: String {
        switch self {
        case .googleDrive: "icloud"
        case .drives: "externaldrive"
        case .sync: "arrow.triangle.2.circlepath"
        case .app: "gearshape"
        }
    }
}

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var selectedTab: SettingsTab = .googleDrive

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 520, height: 480)
    }

    @ViewBuilder
    private func tabContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .googleDrive: GoogleDriveTab(appState: appState)
        case .drives: DrivesTab(appState: appState)
        case .sync: SyncTab(appState: appState)
        case .app: AppTab(appState: appState)
        }
    }
}
