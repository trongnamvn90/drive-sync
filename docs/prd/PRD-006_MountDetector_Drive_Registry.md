# PRD-006: MountDetector + Drive Registry

## Mục tiêu

Detect ổ cứng cắm/rút realtime bằng DiskArbitration framework, và quản lý danh sách ổ đã đăng ký (Drive Registry). Đây là prerequisite cho sync — không detect mount thì không biết khi nào sync, không có registry thì không biết ổ nào sync.

## Scope

| Trong scope | Ngoài scope |
|-------------|-------------|
| MountDetector: detect mount/unmount events | SyncEngine (khi nào gọi rclone) |
| Lấy volume UUID, name, filesystem, capacity | Symlink management (~/Drive) |
| Drive Registry: register/unregister ổ | Format drive |
| Persist registry vào `drives.json` | Wipe data on unregister |
| Wire DrivesTab + RegisterDriveSheet vào data thật | CLI commands |
| Notification khi cắm ổ chưa register | Sync flow triggers |

## Nguyên tắc

**MountDetector là sensor, không quyết định.** Nó chỉ phát event "ổ A vừa cắm", "ổ B vừa rút". Logic xử lý (sync, notification, UI update) nằm ở AppState hoặc SyncEngine (PRD sau).

**Registry là gatekeeper.** Không có trong registry = không sync. An toàn tuyệt đối — không bao giờ sync vào ổ lạ.

---

## Phần A: MountDetector

### Tổng quan

`MountDetector` dùng DiskArbitration framework để nhận callback khi macOS mount/unmount volume. Chỉ quan tâm **external drives** (USB, Thunderbolt), lọc bỏ internal disk, disk images, network volumes.

### ExternalDrive struct

```swift
struct ExternalDrive: Identifiable, Codable, Sendable {
    let id: String           // volume UUID (primary identifier)
    let name: String         // volume name, e.g. "ZORRO"
    let filesystem: String   // "ExFAT", "APFS", "HFS+"
    let capacity: Int64      // bytes
    let mountPoint: String   // "/Volumes/ZORRO"

    var capacityText: String {
        ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
    }
}
```

- `id` = volume UUID từ `DADiskCopyDescription` key `kDAVolumeUUIDKey`
- Một số ổ (đặc biệt FAT32 cũ) có thể **không có UUID** → dùng `kDAMediaBSDNameKey` + `kDAVolumeNameKey` tổng hợp fallback ID
- `Codable` để serialize khi cần

### MountDetector actor

```swift
actor MountDetector {
    static let shared = MountDetector()

    /// Start listening for mount/unmount events
    func start()

    /// Stop listening
    func stop()

    /// Stream of mount events
    func events() -> AsyncStream<MountEvent>

    /// Currently connected external drives (snapshot)
    func connectedDrives() -> [ExternalDrive]
}

enum MountEvent: Sendable {
    case mounted(ExternalDrive)
    case unmounted(volumeUUID: String)
}
```

### DiskArbitration integration

```swift
// Pseudocode — actual implementation trong .swift file

private let session = DASessionCreate(kCFAllocatorDefault)

func start() {
    // Register mount callback
    DARegisterDiskAppearedCallback(session, nil, context) { disk, context in
        let desc = DADiskCopyDescription(disk)
        // Extract UUID, name, filesystem, capacity, mountPoint
        // Filter: only external, removable, or USB/Thunderbolt
        // Emit MountEvent.mounted(drive)
    }

    // Register unmount callback
    DARegisterDiskDisappearedCallback(session, nil, context) { disk, context in
        // Extract UUID
        // Emit MountEvent.unmounted(volumeUUID:)
    }

    // Schedule on RunLoop
    DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
}
```

### Filter logic — chỉ external drives

Lọc bằng `DADiskCopyDescription` keys:

| Key | Điều kiện | Lý do |
|-----|-----------|-------|
| `kDADeviceProtocolKey` | `"USB"` hoặc `"Thunderbolt"` hoặc `"SATA"` | Chỉ physical drives |
| `kDAMediaRemovableKey` | `true` preferred, nhưng không bắt buộc | USB HDD thường non-removable nhưng vẫn external |
| `kDAVolumeMountableKey` | `true` | Phải mountable |
| `kDAVolumePathKey` | not nil, starts with `/Volumes/` | Phải đã mount |
| `kDAMediaWholeKey` | `false` | Partition, không phải whole disk |
| `kDADeviceInternalKey` | `false` | Loại bỏ internal disk |

**Không dùng** `kDAMediaRemovableKey` làm filter chính — nhiều USB HDD (WD, Seagate) báo `removable = false` dù là external.

**Filter chính:** `internal = false` AND `mountable = true` AND `volumePath` starts with `/Volumes/`.

### Initial scan

Khi `start()` được gọi, DiskArbitration **tự động fire callback cho tất cả volumes hiện có**. Không cần scan riêng. Các ổ đã cắm sẵn sẽ emit `MountEvent.mounted` ngay.

### Thread safety

- `DASession` schedule trên main RunLoop → callbacks trên main thread
- Actor isolation đảm bảo internal state thread-safe
- Callbacks bridge sang actor bằng `Task { await self.handleMount(drive) }`

---

## Phần B: Drive Registry

### Tổng quan

Registry lưu danh sách ổ đã đăng ký. Identify bằng **volume UUID**. Persist vào `~/.config/drivesync/drives.json` (tách riêng khỏi config.toml — structured data phù hợp JSON + Codable hơn TOML array).

### RegisteredDrive struct

```swift
struct RegisteredDrive: Identifiable, Codable, Sendable {
    let id: String           // volume UUID (matches ExternalDrive.id)
    var label: String        // user-defined, e.g. "Ổ nhà", "Office Drive"
    let registeredAt: Date   // khi nào đăng ký
    var lastSyncAt: Date?    // lần sync gần nhất (SyncEngine cập nhật sau)
}
```

### DriveRegistry actor

```swift
actor DriveRegistry {
    static let shared = DriveRegistry()

    /// All registered drives
    func all() -> [RegisteredDrive]

    /// Check if a volume UUID is registered
    func isRegistered(volumeUUID: String) -> Bool

    /// Register a new drive
    func register(volumeUUID: String, label: String) throws -> RegisteredDrive

    /// Remove a drive from registry
    func unregister(volumeUUID: String)

    /// Update label
    func updateLabel(volumeUUID: String, label: String)

    /// Update last sync time (called by SyncEngine later)
    func updateLastSync(volumeUUID: String, date: Date)
}
```

### Persistence — drives.json

File: `~/.config/drivesync/drives.json`

```json
[
    {
        "id": "A1B2C3D4-E5F6-G7H8-I9J0-K1L2M3N4O5P6",
        "label": "Ổ nhà",
        "registeredAt": "2026-03-09T16:30:00Z",
        "lastSyncAt": null
    },
    {
        "id": "X9Y8Z7W6-V5U4-T3S2-R1Q0-P9O8N7M6L5K4",
        "label": "Ổ công ty",
        "registeredAt": "2026-03-09T17:00:00Z",
        "lastSyncAt": "2026-03-09T22:15:00Z"
    }
]
```

- Encoding: UTF-8, pretty-printed JSON
- File permissions: `0644` (không nhạy cảm như auth.json)
- File không tồn tại = empty registry (first launch)
- Load khi app start, save ngay sau mỗi thay đổi

### Register flow

```
User bấm "Register New Drive"
    │
    ▼
Sheet mở → gọi MountDetector.connectedDrives()
    │
    ▼
Hiện list ổ external đang cắm (data thật, không mock)
    │
    ├─ Không có ổ nào → "No external drives found. Plug in a drive."
    │
    └─ Có ổ → user chọn ổ + đặt label
         │
         ├─ UUID đã trong registry → BLOCK, hiện warning
         │
         └─ UUID chưa có → bấm Register
              │
              ▼
         DriveRegistry.register(uuid, label)
              │
              ▼
         Save drives.json → update AppState.drives
              │
              ▼
         Log: [INFO] Drive registered: "Ổ nhà" (UUID: A1B2...)
```

### Unregister flow

```
User bấm Remove trên DriveCard
    │
    ▼
Confirm dialog: "Remove 'Ổ nhà' from DriveSync?"
    │
    ▼
DriveRegistry.unregister(uuid)
    │
    ▼
Save drives.json → update AppState.drives
    │
    ▼
Log: [INFO] Drive removed: "Ổ nhà" (UUID: A1B2...)
```

### Duplicate UUID protection

- `DriveRegistry.register()` throws nếu UUID đã tồn tại
- UI: RegisterDriveSheet kiểm tra và disable nút Register + hiện warning
- Edge case: 2 ổ vật lý cùng UUID (clone partition) → bắt buộc format lại 1 ổ để tạo UUID mới

---

## Phần C: Wire vào AppState + UI

### DriveDisplayInfo — unified view model

`AppState` tổng hợp data từ `DriveRegistry` (persistent) + `MountDetector` (live connection status) thành 1 view model:

```swift
struct DriveDisplayInfo: Identifiable {
    let id: String              // volume UUID
    var label: String           // from registry
    var volumeName: String?     // from MountDetector (nil if not connected)
    var filesystem: String?     // from MountDetector
    var capacity: String?       // from MountDetector
    var mountPoint: String?     // from MountDetector
    var registeredAt: Date
    var lastSyncAt: Date?
    var isConnected: Bool       // MountDetector says it's currently mounted
}
```

- `isConnected = true` khi MountDetector có ổ với cùng UUID đang mount
- `volumeName`, `filesystem`, `capacity` chỉ có khi connected (live data)
- Khi disconnected: hiện label + UUID + last sync time, còn lại hiện "—"

### AppState thay đổi

```swift
// Bỏ mock data, thay bằng:
var drives: [DriveDisplayInfo] = []

// Properties mới
private var mountDetector: MountDetector { MountDetector.shared }
private var driveRegistry: DriveRegistry { DriveRegistry.shared }

// Khởi tạo khi app launch
func startMountDetection() {
    Task {
        await mountDetector.start()

        for await event in await mountDetector.events() {
            switch event {
            case .mounted(let drive):
                handleDriveMount(drive)
            case .unmounted(let uuid):
                handleDriveUnmount(uuid)
            }
        }
    }

    // Load registry
    Task {
        await refreshDriveList()
    }
}

private func handleDriveMount(_ drive: ExternalDrive) {
    let isRegistered = /* check registry */
    if isRegistered {
        // Update drives list: mark as connected
        await refreshDriveList()
        await LogManager.shared.info("Drive mounted: \"\(drive.name)\" (UUID: \(drive.id.prefix(8))...)")
    } else {
        // Notification: ổ chưa đăng ký
        sendNotification(
            title: "Unknown Drive",
            body: "\"\(drive.name)\" is not registered. Open DriveSync to add it."
        )
        await LogManager.shared.info("Unknown drive mounted: \"\(drive.name)\" (UUID: \(drive.id.prefix(8))...) — not in registry")
    }
}

private func handleDriveUnmount(_ uuid: String) {
    // Update drives list: mark as disconnected
    await refreshDriveList()
    await LogManager.shared.info("Drive unmounted (UUID: \(uuid.prefix(8))...)")
}

/// Rebuild drives list from registry + mount status
func refreshDriveList() async {
    let registered = await driveRegistry.all()
    let connected = await mountDetector.connectedDrives()

    drives = registered.map { reg in
        let live = connected.first { $0.id == reg.id }
        return DriveDisplayInfo(
            id: reg.id,
            label: reg.label,
            volumeName: live?.name,
            filesystem: live?.filesystem,
            capacity: live?.capacityText,
            mountPoint: live?.mountPoint,
            registeredAt: reg.registeredAt,
            lastSyncAt: reg.lastSyncAt,
            isConnected: live != nil
        )
    }
}
```

### RegisterDriveSheet — bỏ mock, dùng data thật

```swift
// Thay mockDrives bằng:
@State private var availableDrives: [ExternalDrive] = []
@State private var loading = true

.task {
    availableDrives = await MountDetector.shared.connectedDrives()
    // Filter ra ổ đã registered
    let registered = await DriveRegistry.shared.all()
    let registeredUUIDs = Set(registered.map(\.id))
    // Đánh dấu ổ nào đã register (để hiện warning, không lọc bỏ)
    loading = false
}
```

Hiện list ổ thật với thông tin từ DiskArbitration. Ổ đã register → hiện warning + disable nút Register.

### DrivesTab — wire remove vào DriveRegistry

```swift
private func removeDrive(_ drive: DriveDisplayInfo) {
    Task {
        await DriveRegistry.shared.unregister(volumeUUID: drive.id)
        await appState.refreshDriveList()
        await LogManager.shared.info("Drive removed: \"\(drive.label)\" (UUID: \(drive.id.prefix(8))...)")
    }
}
```

### DriveCard — hiện data thật

Cập nhật DriveCard để handle connected vs disconnected:

```
Connected:
🟢 Home Drive                    [✏️] [Remove]
   ZORRO • UUID: A1B2C3D4...
   ExFAT • 500 GB
   Last sync: 14:32 today

Disconnected:
⚫ Office Drive                   [✏️] [Remove]
   UUID: E5F6G7H8...
   Last sync: 22:15 yesterday
```

- Connected: hiện volume name, filesystem, capacity (live data)
- Disconnected: chỉ hiện UUID + last sync (registry data)

### MenuDropdownView — đã sẵn sàng

`warningHeader` đã check `appState.drives.isEmpty` → khi registry trống, tự hiện "No drives registered". Không cần sửa.

---

## Logging

| Event | Log |
|-------|-----|
| MountDetector started | `[INFO] MountDetector started` |
| External drive mounted (registered) | `[INFO] Drive mounted: "ZORRO" (UUID: A1B2...)` |
| External drive mounted (not registered) | `[INFO] Unknown drive mounted: "ZORRO" (UUID: A1B2...) — not in registry` |
| Drive unmounted | `[INFO] Drive unmounted (UUID: A1B2...)` |
| Drive registered | `[INFO] Drive registered: "Ổ nhà" (UUID: A1B2...)` |
| Drive removed | `[INFO] Drive removed: "Ổ nhà" (UUID: A1B2...)` |
| Drive label updated | `[INFO] Drive label updated: "Ổ nhà" → "Home Drive" (UUID: A1B2...)` |
| Registry loaded | `[DEBUG] Drive registry loaded: 2 drive(s)` |
| Registry saved | `[DEBUG] Drive registry saved: 2 drive(s)` |
| No UUID found for disk | `[WARN] External drive "ZORRO" has no volume UUID — using fallback ID` |

---

## Files cần tạo / sửa

### Tạo mới

| File | Mô tả |
|------|-------|
| `Sources/DriveSync/Core/Mount/MountDetector.swift` | DiskArbitration actor, AsyncStream events |
| `Sources/DriveSync/Core/Mount/ExternalDrive.swift` | ExternalDrive struct |
| `Sources/DriveSync/Core/Mount/DriveRegistry.swift` | Registry actor, drives.json persistence |

### Sửa

| File | Thay đổi |
|------|----------|
| `Sources/DriveSync/Models/SyncState.swift` | Thay `DriveInfo` bằng `DriveDisplayInfo`. Bỏ mock fields. |
| `Sources/DriveSync/ViewModels/AppState.swift` | Bỏ mock drives. Thêm `startMountDetection()`, `refreshDriveList()`, `handleDriveMount/Unmount`. Wire register/unregister. |
| `Sources/DriveSync/DriveSyncApp.swift` | Gọi `appState.startMountDetection()` trong `applicationDidFinishLaunching`. |
| `Sources/DriveSync/Views/Settings/RegisterDriveSheet.swift` | Bỏ mockDrives. Load từ `MountDetector.connectedDrives()`. Wire register vào DriveRegistry. |
| `Sources/DriveSync/Views/Settings/DrivesTab.swift` | Wire remove vào DriveRegistry. Update DriveCard cho connected/disconnected display. |
| `Package.swift` | Có thể cần thêm DiskArbitration framework linking (thường tự có trên macOS, nhưng verify). |

### Không sửa

- `ConfigManager.swift` — registry tách riêng, không ảnh hưởng
- `GoogleDriveTab.swift`, `SyncTab.swift`, `AppTab.swift` — không liên quan
- `LogManager.swift` — chỉ gọi, không sửa
- `MenuDropdownView.swift` — logic `drives.isEmpty` đã có sẵn

---

## Edge Cases

| Tình huống | Xử lý |
|------------|--------|
| Ổ không có volume UUID (FAT32 cũ) | Fallback ID từ BSD name + volume name. Log warning. |
| 2 ổ cùng UUID (clone partition) | Register chặn trùng UUID. UI hiện warning + gợi ý format. |
| Cắm ổ khi app chưa launch | MountDetector.start() fire initial scan → bắt kịp. |
| drives.json bị xóa/corrupt | Coi như empty registry. Log warning. App vẫn chạy. |
| drives.json bị corrupt (invalid JSON) | Backup file cũ thành `.bak`, tạo mới. Log error. |
| Cắm 2 ổ registered cùng lúc | Cả 2 đều `isConnected = true`. SyncEngine (PRD sau) quyết định sync ổ nào. |
| Rút ổ rất nhanh sau khi cắm | Unmount event fire → cancel mount handling nếu chưa xong. |
| Internal disk partition mới | Filter loại bỏ: `internal = true`. Không bao giờ hiện trong list. |
| Disk image (.dmg) mounted | Filter loại bỏ: `DADeviceModelKey` chứa "Disk Image". |

---

## Acceptance Criteria

### MountDetector

- [ ] Detect external USB/Thunderbolt drive mount trong < 2 giây
- [ ] Detect unmount khi rút ổ hoặc eject từ Finder
- [ ] Lấy đúng volume UUID từ DiskArbitration
- [ ] Lấy đúng volume name, filesystem, capacity, mount point
- [ ] Không detect internal disk, disk images, network volumes
- [ ] Ổ đã cắm sẵn trước khi app launch → vẫn detect được (initial scan)
- [ ] AsyncStream<MountEvent> broadcast đúng events
- [ ] Fallback ID khi ổ không có UUID + log warning

### Drive Registry

- [ ] Register drive → persist vào drives.json ngay lập tức
- [ ] Unregister → remove khỏi drives.json
- [ ] Chặn register UUID đã tồn tại (throws error)
- [ ] Update label → persist
- [ ] Load registry khi app start
- [ ] drives.json không tồn tại → empty registry, không lỗi
- [ ] drives.json corrupt → backup + tạo mới + log error

### UI — DrivesTab

- [ ] Hiện danh sách drives từ registry (không mock)
- [ ] 🟢 dot khi ổ đang cắm, ⚫ khi rút
- [ ] Connected: hiện volume name, filesystem, capacity
- [ ] Disconnected: hiện UUID + last sync, không hiện volume info
- [ ] Remove → confirm → unregister → refresh list

### UI — RegisterDriveSheet

- [ ] Hiện list ổ external thật đang cắm
- [ ] Không có ổ nào → "No external drives found. Plug in a drive."
- [ ] Chỉ 1 ổ → tự chọn sẵn
- [ ] UUID đã register → warning + disable Register button
- [ ] Bấm Register → save registry → close sheet → refresh list
- [ ] Label field bắt buộc (không cho empty)

### Integration

- [ ] Cắm ổ registered → `isConnected` update, DriveCard hiện 🟢
- [ ] Rút ổ → `isConnected = false`, DriveCard hiện ⚫
- [ ] Cắm ổ chưa register → macOS notification cảnh báo
- [ ] Menu dropdown hiện "No drives registered" khi registry trống
- [ ] Tất cả events ghi log đúng format

---

## Không làm (deferred)

| Item | Lý do |
|------|-------|
| Format drive từ trong app | Phức tạp, cần DiskManagement private framework. User tự format bằng Disk Utility. |
| Wipe data on unregister | Nguy hiểm, cần thêm safety layer. Để v2. |
| Edit drive label từ DriveCard (pencil icon) | Nice-to-have, không critical. Wire sau khi core hoạt động. |
| CLI `drivesync register/unregister` | CLI layer chưa implement. |
| Auto-register prompt khi cắm ổ lạ | Notification đủ rồi. User tự vào Settings. |

---

**Author:** Claude (Minh Thư) — 2026-03-09

## ⚠️ Implementation Status

**Partially tested** — Code written 2026-03-10. Bugfix for delayed mount paths pushed same day.

### Test Results (2026-03-10)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | `swift build` compiles | ✅ Pass | DiskArbitration linked OK |
| 2 | App launches | ✅ Pass | Menubar icon hiện |
| 3 | Plug USB → detect | ✅ Pass | Retry mechanism, ExFAT + APFS |
| 4 | Register drive + JSON persist | ✅ Pass | `~/.config/drivesync/drives.json` |
| 5 | Connected → green dot, volume info | ❓ Not confirmed | Cần confirm UI hiện xanh |
| 6 | Eject → gray dot, UUID only | ❓ Not confirmed | Unmount event fire đúng, cần confirm UI |
| 7 | Unregister → gone from list + JSON | ✅ Pass | |
| 8 | Unknown drive → macOS notification | ❓ Not tested | Cắm ổ chưa register, check notification |
| 9 | App restart → persist + connected | ✅ Pass | |
| 10 | Empty state → menu "No drives registered" | ❓ Not tested | Xóa hết drives rồi check menu |

### Known Issues Fixed
- DA callbacks fire before mount completes → added retry with fresh `DADiskCreateFromBSDName`
- APFS synthesized volumes report `internal=true` → parent disk check
- DA-level filter too restrictive → removed, filter in parse function instead
