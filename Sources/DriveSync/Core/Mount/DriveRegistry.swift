import Foundation

struct RegisteredDrive: Identifiable, Codable, Sendable {
    let id: String           // volume UUID
    let label: String
    let registeredAt: Date
    var lastSyncAt: Date?
}

actor DriveRegistry {
    static let shared = DriveRegistry()

    private let fileURL: URL
    private var drives: [RegisteredDrive] = []
    private var loaded = false

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/drivesync")
        self.fileURL = dir.appendingPathComponent("drives.json")
    }

    // MARK: - Public API

    func all() -> [RegisteredDrive] {
        ensureLoaded()
        return drives
    }

    func isRegistered(_ volumeId: String) -> Bool {
        ensureLoaded()
        return drives.contains { $0.id == volumeId }
    }

    func register(volumeId: String, label: String) throws -> RegisteredDrive {
        ensureLoaded()
        guard !drives.contains(where: { $0.id == volumeId }) else {
            throw DriveRegistryError.alreadyRegistered(volumeId)
        }
        let drive = RegisteredDrive(id: volumeId, label: label, registeredAt: Date())
        drives.append(drive)
        try save()
        Task { await LogManager.shared.info("📝 Drive registered: \"\(label)\" (\(volumeId.prefix(8))...)") }
        return drive
    }

    func unregister(_ volumeId: String) throws {
        ensureLoaded()
        drives.removeAll { $0.id == volumeId }
        try save()
        Task { await LogManager.shared.info("🗑️ Drive unregistered: \(volumeId.prefix(8))...") }
    }

    func updateLabel(_ volumeId: String, label: String) throws {
        ensureLoaded()
        guard let idx = drives.firstIndex(where: { $0.id == volumeId }) else { return }
        drives[idx] = RegisteredDrive(
            id: drives[idx].id,
            label: label,
            registeredAt: drives[idx].registeredAt,
            lastSyncAt: drives[idx].lastSyncAt
        )
        try save()
    }

    func updateLastSync(_ volumeId: String, date: Date = Date()) throws {
        ensureLoaded()
        guard let idx = drives.firstIndex(where: { $0.id == volumeId }) else { return }
        drives[idx] = RegisteredDrive(
            id: drives[idx].id,
            label: drives[idx].label,
            registeredAt: drives[idx].registeredAt,
            lastSyncAt: date
        )
        try save()
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        do {
            try load()
        } catch {
            Task { await LogManager.shared.error("❌ Failed to load drives.json: \(error.localizedDescription)") }
            // Backup corrupt file and start fresh
            let backupURL = fileURL.deletingPathExtension().appendingPathExtension("bak")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            drives = []
        }
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            drives = []
            return
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        drives = try decoder.decode([RegisteredDrive].self, from: data)
    }

    private func save() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(drives)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum DriveRegistryError: LocalizedError {
    case alreadyRegistered(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRegistered(let id): "Drive \(id.prefix(8))... is already registered"
        }
    }
}
