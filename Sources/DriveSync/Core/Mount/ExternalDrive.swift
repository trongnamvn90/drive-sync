import Foundation

struct ExternalDrive: Identifiable, Codable, Sendable, Equatable {
    let id: String           // volume UUID or fallback "bsd:disk2s1+ZORRO"
    let name: String         // "ZORRO"
    let filesystem: String   // "ExFAT", "APFS"
    let capacity: Int64      // bytes
    let mountPoint: String   // "/Volumes/ZORRO"

    var capacityText: String {
        ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
    }
}

enum MountEvent: Sendable {
    case mounted(ExternalDrive)
    case unmounted(volumeId: String)
}
