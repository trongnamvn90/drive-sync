import SwiftUI

@main
struct DriveSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuDropdownView(appState: appDelegate.appState)
        } label: {
            MenuBarIcon(appState: appDelegate.appState)
        }

        Settings {
            SettingsView(appState: appDelegate.appState)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }

        Window("About DriveSync", id: "about") {
            AboutView()
        }
        .defaultSize(width: 320, height: 400)
        .windowResizability(.contentSize)
    }
}

struct MenuBarIcon: View {
    var appState: AppState

    var body: some View {
        let icon = loadIcon(for: appState.currentState)
        if let icon {
            Image(nsImage: icon)
        } else {
            Image(systemName: "externaldrive.fill.badge.icloud")
        }
    }

    private func loadIcon(for state: SyncState) -> NSImage? {
        guard let url = Bundle.module.url(forResource: state.iconName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire up GoogleAuthService with real dependencies
        let httpClient = URLSessionHTTPClient()
        let tokenStore = TokenManager()
        appState.authService = GoogleAuthService(httpClient: httpClient, tokenStore: tokenStore)

        // Logging startup + cleanup
        Task {
            await LogManager.shared.syncMinLevelFromConfig()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            await LogManager.shared.info("DriveSync started (v\(version))")
            await LogManager.shared.deleteOldLogs(keepDays: appState.keepLogsDays)
        }

        // Restore saved session
        appState.loadSavedAuth()

        // Sync launch-at-login with system + request notification permission
        appState.setupOnLaunch()

        // Log shutdown
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            Task {
                await LogManager.shared.info("DriveSync shutting down")
                await LogManager.shared.flush()
            }
        }
    }
}
