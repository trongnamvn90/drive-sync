import SwiftUI
import Combine
import ServiceManagement
import UserNotifications

enum GoogleConnectionState {
    case disconnected
    case connecting
    case connected
}

struct GoogleAccount {
    var email: String
    var storageUsed: Int64   // bytes
    var storageTotal: Int64  // bytes

    var storageUsedText: String {
        ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file)
    }

    var storageTotalText: String {
        ByteCountFormatter.string(fromByteCount: storageTotal, countStyle: .file)
    }

    var storageFraction: Double {
        guard storageTotal > 0 else { return 0 }
        return Double(storageUsed) / Double(storageTotal)
    }
}

@MainActor
@Observable
final class AppState {
    let config = ConfigManager.shared
    var currentState: SyncState = .idle

    // Google Drive
    var googleState: GoogleConnectionState = .disconnected
    var googleAccount: GoogleAccount?
    var googleFolders: [GoogleDriveFolder] = []
    var errorMessage: String?

    var googleFolder: String {
        didSet {
            config.set(section: "google", key: "folder", value: googleFolder)
            Task { await LogManager.shared.info("Settings changed: google.folder = \"\(googleFolder)\"") }
        }
    }
    var uploadLimit: Int {
        didSet {
            config.set(section: "google", key: "upload_limit", value: uploadLimit)
            Task { await LogManager.shared.info("Settings changed: upload_limit = \(uploadLimit)") }
        }
    }
    var downloadLimit: Int {
        didSet {
            config.set(section: "google", key: "download_limit", value: downloadLimit)
            Task { await LogManager.shared.info("Settings changed: download_limit = \(downloadLimit)") }
        }
    }

    // Sync
    var debounceSec: Int {
        didSet {
            config.set(section: "sync", key: "debounce_sec", value: debounceSec)
            Task { await LogManager.shared.info("Settings changed: debounce_sec = \(debounceSec)") }
        }
    }
    var periodicSyncMin: Int {
        didSet {
            config.set(section: "sync", key: "periodic_sync_min", value: periodicSyncMin)
            Task { await LogManager.shared.info("Settings changed: periodic_sync_min = \(periodicSyncMin)") }
        }
    }
    var onDeleteAction: String {
        didSet {
            config.set(section: "sync", key: "on_delete", value: onDeleteAction)
            Task { await LogManager.shared.info("Settings changed: on_delete = \"\(onDeleteAction)\"") }
        }
    }

    // App
    var launchAtLogin: Bool {
        didSet {
            config.set(section: "app", key: "launch_at_login", value: launchAtLogin)
            updateLaunchAtLogin()
            Task { await LogManager.shared.info("Settings changed: launch_at_login = \(launchAtLogin)") }
        }
    }
    var showNotifications: Bool {
        didSet {
            config.set(section: "app", key: "show_notifications", value: showNotifications)
            if showNotifications { requestNotificationPermission() }
            Task { await LogManager.shared.info("Settings changed: show_notifications = \(showNotifications)") }
        }
    }
    var symlinkPath: String {
        didSet {
            config.set(section: "app", key: "symlink_path", value: symlinkPath)
            Task { await LogManager.shared.info("Settings changed: symlink_path = \"\(symlinkPath)\"") }
        }
    }
    var logLevel: String {
        didSet {
            config.set(section: "app", key: "log_level", value: logLevel)
            Task {
                let level = LogLevel(rawValue: logLevel.uppercased()) ?? .info
                await LogManager.shared.setMinLevel(level)
                await LogManager.shared.info("Settings changed: log_level = \"\(logLevel)\"")
            }
        }
    }
    var keepLogsDays: Int {
        didSet {
            config.set(section: "app", key: "keep_logs_days", value: keepLogsDays)
            Task { await LogManager.shared.info("Settings changed: keep_logs_days = \(keepLogsDays)") }
        }
    }

    init() {
        // Load persisted values (or defaults)
        self.googleFolder = config.string(section: "google", key: "folder") ?? "DriveSync"
        self.uploadLimit = config.int(section: "google", key: "upload_limit") ?? 0
        self.downloadLimit = config.int(section: "google", key: "download_limit") ?? 0
        self.debounceSec = config.int(section: "sync", key: "debounce_sec") ?? 30
        self.periodicSyncMin = config.int(section: "sync", key: "periodic_sync_min") ?? 15
        self.onDeleteAction = config.string(section: "sync", key: "on_delete") ?? "Move to Trash"
        self.launchAtLogin = config.bool(section: "app", key: "launch_at_login") ?? true
        self.showNotifications = config.bool(section: "app", key: "show_notifications") ?? true
        self.symlinkPath = config.string(section: "app", key: "symlink_path") ?? "~/Drive"
        self.logLevel = config.string(section: "app", key: "log_level") ?? "info"
        self.keepLogsDays = config.int(section: "app", key: "keep_logs_days") ?? 30

    }

    // Drives
    var drives: [DriveInfo] = [
        DriveInfo(
            label: "Home Drive", volumeName: "ZORRO", uuid: "A1B2C3D4",
            filesystem: "exFAT", capacity: "500GB",
            lastSync: "14:32 today", isConnected: true
        ),
        DriveInfo(
            label: "Office Drive", volumeName: "ZORRO", uuid: "E5F6G7H8",
            filesystem: "exFAT", capacity: "500GB",
            lastSync: "22:15 yesterday", isConnected: false
        ),
    ]

    // Sync progress
    var syncProgress: Double = 0.45
    var syncFilesTotal = 10
    var syncFilesDone = 3
    var syncBytesTotal = "260MB"
    var syncBytesDone = "120MB"

    // Logs — fed by LogManager stream, no more mock data

    // --- Google OAuth ---

    var authService: GoogleAuthService?
    private var connectTask: Task<Void, Never>?

    func connectGoogle() {
        guard let authService else { return }
        errorMessage = nil
        googleState = .connecting

        connectTask = Task {
            await LogManager.shared.info("Google OAuth connecting...")
            do {
                let account = try await authService.connect()
                self.googleAccount = GoogleAccount(
                    email: account.email,
                    storageUsed: account.storageUsed,
                    storageTotal: account.storageTotal
                )
                self.googleFolders = account.folders
                self.googleState = .connected
                await LogManager.shared.info("Google OAuth connected: \(account.email)")
            } catch let error as GoogleAuthError where error == .cancelled {
                self.googleState = .disconnected
                await LogManager.shared.info("Google OAuth cancelled by user")
            } catch {
                self.googleState = .disconnected
                if let authError = error as? GoogleAuthError {
                    self.errorMessage = authError.userMessage
                    await LogManager.shared.error("Google OAuth error: \(authError.userMessage)")
                } else if !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                    await LogManager.shared.error("Google OAuth error: \(error.localizedDescription)")
                }
            }
        }
    }

    func disconnectGoogle() {
        let service = authService
        googleState = .disconnected
        googleAccount = nil
        googleFolders = []
        errorMessage = nil

        Task {
            try? await service?.disconnect()
            await LogManager.shared.info("Google OAuth disconnected")
        }
    }

    func reloginGoogle() {
        Task { await LogManager.shared.info("Google OAuth re-login initiated") }
        disconnectGoogle()
        connectGoogle()
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        googleState = .disconnected
    }

    func loadSavedAuth() {
        guard let authService else { return }

        Task {
            do {
                guard let account = try await authService.loadOnStartup() else { return }
                self.googleAccount = GoogleAccount(
                    email: account.email,
                    storageUsed: account.storageUsed,
                    storageTotal: account.storageTotal
                )
                self.googleFolders = account.folders
                self.googleState = .connected
                await LogManager.shared.info("Loaded saved auth: \(account.email)")
            } catch {
                await LogManager.shared.warn("Failed to load saved auth: \(error.localizedDescription)")
            }
        }
    }

    func setupOnLaunch() {
        updateLaunchAtLogin()
        if showNotifications { requestNotificationPermission() }
    }

    // --- Launch at Login ---

    private func updateLaunchAtLogin() {
        let service = SMAppService.mainApp
        if launchAtLogin {
            try? service.register()
        } else {
            try? service.unregister()
        }
    }

    // --- Notifications ---

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func requestNotificationPermission() {
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendNotification(title: String, body: String) {
        guard showNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter?.add(request)
    }

    // --- Log File ---

    func openLogFile() {
        let url = LogManager.todayLogFileURL()
        let fm = FileManager.default
        try? fm.createDirectory(at: LogManager.logDirectory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.open(url)
    }

    // --- Icon cycling (demo) ---

    private var iconTimer: Timer?
    private var stateIndex = 0

    func startIconCycling() {
        stateIndex = 0
        currentState = SyncState.allCases[stateIndex]
        iconTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stateIndex = (self.stateIndex + 1) % SyncState.allCases.count
                self.currentState = SyncState.allCases[self.stateIndex]
            }
        }
    }

    func stopIconCycling() {
        iconTimer?.invalidate()
        iconTimer = nil
    }
}
