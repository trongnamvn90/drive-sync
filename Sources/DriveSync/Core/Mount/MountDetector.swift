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
    private var pendingDisks: [String: DADisk] = [:]  // BSD name → disk, waiting for mount path

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

        // No DA-level filter — we filter in parseExternalDrive() instead,
        // because APFS external drives have synthesized volumes that DA
        // reports as "internal" even though the physical store is external.
        DARegisterDiskAppearedCallback(newSession, nil, { disk, ctx in
            guard let ctx else { return }
            let detector = Unmanaged<MountDetector>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                detector.handleDiskAppeared(disk)
            }
        }, ptr)

        DARegisterDiskDisappearedCallback(newSession, nil, { disk, ctx in
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
        // Debug: log all disk events
        let bsd = DADiskGetBSDName(disk).flatMap { String(cString: $0) } ?? "?"
        if let desc = DADiskCopyDescription(disk) as? [CFString: Any] {
            let name = desc[kDADiskDescriptionVolumeNameKey] as? String ?? "nil"
            let path = (desc[kDADiskDescriptionVolumePathKey] as? URL)?.path ?? "nil"
            let isInternal = desc[kDADiskDescriptionDeviceInternalKey] as? Bool
            Task { await LogManager.shared.info("💿 DA appeared: \(bsd) name=\(name) path=\(path) internal=\(String(describing: isInternal))") }
        }

        guard let drive = parseExternalDrive(from: disk) else {
            // Disk may still be mounting (path=nil). Retry for any non-internal,
            // non-network disk that doesn't have a mount path yet.
            if let desc = DADiskCopyDescription(disk) as? [CFString: Any],
               (desc[kDADiskDescriptionVolumePathKey] as? URL) == nil,
               desc[kDADiskDescriptionVolumeNetworkKey] as? Bool != true,
               desc[kDADiskDescriptionMediaWholeKey] as? Bool != true {
                pendingDisks[bsd] = disk
                Task { await LogManager.shared.info("💿 DA appeared \(bsd) — no mount path yet, will retry") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.retryPendingDisk(bsd: bsd)
                }
            } else {
                Task { await LogManager.shared.info("💿 DA appeared \(bsd) — filtered out") }
            }
            return
        }
        pendingDisks.removeValue(forKey: bsd)
        connectedDrivesMap[drive.id] = drive
        for c in continuations.values { c.yield(.mounted(drive)) }
        Task { await LogManager.shared.info("🔌 Drive mounted: \(drive.name) (\(drive.id.prefix(8))...)") }
    }

    private func retryPendingDisk(bsd: String, attempt: Int = 1) {
        guard pendingDisks[bsd] != nil, let session else { return }

        // Re-create DADisk from BSD name to get fresh description (old one is stale)
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsd) else { return }

        if let drive = parseExternalDrive(from: disk) {
            pendingDisks.removeValue(forKey: bsd)
            connectedDrivesMap[drive.id] = drive
            for c in continuations.values { c.yield(.mounted(drive)) }
            Task { await LogManager.shared.info("🔌 Drive mounted (retry #\(attempt)): \(drive.name) (\(drive.id.prefix(8))...)") }
        } else if attempt < 5 {
            // Retry up to 5 times (10 seconds total)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.retryPendingDisk(bsd: bsd, attempt: attempt + 1)
            }
        } else {
            pendingDisks.removeValue(forKey: bsd)
            Task { await LogManager.shared.info("💿 DA disk \(bsd) — gave up after \(attempt) retries, never mounted") }
        }
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

        // Must have a mount path under /Volumes/
        guard let pathURL = desc[kDADiskDescriptionVolumePathKey] as? URL else { return nil }
        let mountPath = pathURL.path
        guard mountPath.hasPrefix("/Volumes/") else { return nil }

        // Skip network volumes
        if desc[kDADiskDescriptionVolumeNetworkKey] as? Bool == true { return nil }

        // Skip disk images
        if let model = desc[kDADiskDescriptionDeviceModelKey] as? String,
           model.contains("Disk Image") { return nil }

        // For APFS: synthesized volumes report internal=true even when physical store is external.
        // We check the device protocol — USB/Thunderbolt/SATA = external.
        // For non-APFS: respect the internal flag directly.
        let isInternal = desc[kDADiskDescriptionDeviceInternalKey] as? Bool ?? false
        // If DA says internal, check if parent whole disk is actually external
        // (APFS synthesized volumes report internal=true even on USB drives)
        if isInternal {
            // Check if parent whole disk is external
            let isParentExternal = checkParentIsExternal(disk)
            if !isParentExternal { return nil }
        }

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

    /// Walk up the disk tree to check if the physical device is external
    private func checkParentIsExternal(_ disk: DADisk) -> Bool {
        // Try to get the whole disk (parent)
        guard let bsdName = DADiskGetBSDName(disk) else { return false }
        let bsd = String(cString: bsdName)

        // Extract base device name (e.g. "disk4" from "disk4s2s1")
        var baseDevice = ""
        var i = bsd.startIndex
        // skip "disk"
        if bsd.hasPrefix("disk") {
            i = bsd.index(bsd.startIndex, offsetBy: 4)
            // collect digits
            while i < bsd.endIndex && bsd[i].isNumber {
                i = bsd.index(after: i)
            }
            baseDevice = String(bsd[bsd.startIndex..<i])
        }

        guard !baseDevice.isEmpty,
              let parentDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session!, baseDevice) else {
            return false
        }

        guard let parentDesc = DADiskCopyDescription(parentDisk) as? [CFString: Any] else { return false }
        let parentInternal = parentDesc[kDADiskDescriptionDeviceInternalKey] as? Bool ?? true
        return !parentInternal
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
