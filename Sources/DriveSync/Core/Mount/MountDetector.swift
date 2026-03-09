import Foundation
import DiskArbitration

// MARK: - MountDetector (@MainActor — DA callbacks run on main run loop)

@MainActor
final class MountDetector {
    static let shared = MountDetector()

    private var session: DASession?
    private var connectedDrivesMap: [String: ExternalDrive] = [:]
    private var continuations: [UUID: AsyncStream<MountEvent>.Continuation] = [:]
    private var retainedSelf: Unmanaged<MountDetector>?

    func start() {
        guard session == nil else { return }
        guard let newSession = DASessionCreate(kCFAllocatorDefault) else {
            Task { await LogManager.shared.error("❌ Failed to create DASession") }
            return
        }
        session = newSession
        DASessionScheduleWithRunLoop(newSession, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        retainedSelf = Unmanaged.passRetained(self)
        let ptr = retainedSelf!.toOpaque()

        let matchDict: [CFString: Any] = [
            kDADiskDescriptionVolumeNetworkKey: false,
            kDADiskDescriptionDeviceInternalKey: false,
            kDADiskDescriptionVolumeMountableKey: true,
            kDADiskDescriptionMediaWholeKey: false,
        ]

        DARegisterDiskAppearedCallback(newSession, matchDict as CFDictionary, { disk, ctx in
            guard let ctx else { return }
            let detector = Unmanaged<MountDetector>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                detector.handleDiskAppeared(disk)
            }
        }, ptr)

        DARegisterDiskDisappearedCallback(newSession, matchDict as CFDictionary, { disk, ctx in
            guard let ctx else { return }
            let detector = Unmanaged<MountDetector>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                detector.handleDiskDisappeared(disk)
            }
        }, ptr)

        Task { await LogManager.shared.info("🔍 MountDetector started — listening for disk events") }
    }

    func stop() {
        if let session {
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        session = nil
        for c in continuations.values { c.finish() }
        continuations.removeAll()
        connectedDrivesMap.removeAll()
        retainedSelf?.release()
        retainedSelf = nil
    }

    func events() -> AsyncStream<MountEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var connectedDrives: [ExternalDrive] {
        Array(connectedDrivesMap.values)
    }

    // MARK: - DA Callbacks

    private func handleDiskAppeared(_ disk: DADisk) {
        guard let drive = parseExternalDrive(from: disk) else { return }
        connectedDrivesMap[drive.id] = drive
        for c in continuations.values { c.yield(.mounted(drive)) }
        Task { await LogManager.shared.info("🔌 Drive mounted: \(drive.name) (\(drive.id.prefix(8))...)") }
    }

    private func handleDiskDisappeared(_ disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [CFString: Any],
              let volumeId = extractVolumeId(from: desc, disk: disk) else { return }
        connectedDrivesMap.removeValue(forKey: volumeId)
        for c in continuations.values { c.yield(.unmounted(volumeId: volumeId)) }
        Task { await LogManager.shared.info("⏏️ Drive unmounted: \(volumeId.prefix(8))...") }
    }

    // MARK: - Parsing

    private func parseExternalDrive(from disk: DADisk) -> ExternalDrive? {
        guard let desc = DADiskCopyDescription(disk) as? [CFString: Any] else { return nil }

        guard let pathURL = desc[kDADiskDescriptionVolumePathKey] as? URL else { return nil }
        let mountPath = pathURL.path
        guard mountPath.hasPrefix("/Volumes/") else { return nil }

        // Skip disk images
        if let model = desc[kDADiskDescriptionDeviceModelKey] as? String,
           model.contains("Disk Image") { return nil }

        let name = desc[kDADiskDescriptionVolumeNameKey] as? String ?? "Untitled"
        let filesystem = desc[kDADiskDescriptionVolumeTypeKey] as? String ?? "Unknown"
        let capacity = (desc[kDADiskDescriptionMediaSizeKey] as? NSNumber)?.int64Value ?? 0

        let volumeId = extractVolumeId(from: desc, disk: disk)
            ?? "bsd:unknown+\(name)"

        return ExternalDrive(
            id: volumeId,
            name: name,
            filesystem: filesystem,
            capacity: capacity,
            mountPoint: mountPath
        )
    }

    private func extractVolumeId(from desc: [CFString: Any], disk: DADisk) -> String? {
        if let cfUUID = desc[kDADiskDescriptionVolumeUUIDKey] {
            // swiftlint:disable:next force_cast
            let uuid = cfUUID as! CFUUID
            if let str = CFUUIDCreateString(kCFAllocatorDefault, uuid) {
                return str as String
            }
        }

        // Fallback: BSD name + volume name
        let bsd = DADiskGetBSDName(disk).flatMap { String(cString: $0) }
        let name = desc[kDADiskDescriptionVolumeNameKey] as? String
        if let bsd, let name {
            return "bsd:\(bsd)+\(name)"
        }

        return nil
    }
}
