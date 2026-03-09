# DriveSync — Technical Design

## Architecture

1 Swift app duy nhất, tách 3 layers:

```
DriveSync.app
│
├─ Core Library (testable, chứa hết logic)
│  ├─ SyncEngine        gọi rclone, logic sync
│  ├─ MountDetector     detect ổ cắm/rút (DiskArbitration)
│  ├─ FileWatcher       detect file thay đổi (FSEvents)
│  ├─ ConflictHandler   xử lý conflict
│  └─ ConfigManager     đọc/ghi config
│
├─ CLI (thin wrapper gọi Core)
│  └─ drivesync sync|status|eject|doctor
│
└─ Menubar UI (thin wrapper gọi Core)
   └─ SwiftUI views
```

| Layer | Vai trò | Test bằng |
|-------|---------|-----------|
| Core | Logic, không UI | Unit test + integration test tự động |
| CLI | Develop & debug, verify nhanh | Script chạy lệnh rồi assert |
| Menubar | User dùng hàng ngày | Manual (logic đã test qua Core) |

**Tại sao 1 app, không tách daemon?**
- Không cần IPC (status.json, control file)
- 1 binary cài, 1 chỗ debug, 1 log
- CLI + Menubar gọi cùng Core → hành vi giống hệt nhau

## Tech Stack

| Component | Tool | Lý do |
|-----------|------|-------|
| App + Core | Swift | Native macOS, type-safe, testable |
| Menubar UI | SwiftUI | Declarative, nhẹ |
| Mount detection | DiskArbitration | macOS native framework |
| File watcher | FSEvents | macOS native, không cần fswatch |
| Sync engine | rclone (Process) | Bisync, incremental, resume, Google Drive API |
| Config | TOML | Dễ đọc |
| Test | XCTest | Swift native |

## Drive Registry

Mỗi ổ cứng phải **register** trước khi sync. Phần mềm identify ổ bằng **volume UUID** (không phải volume name).

```toml
# Registry nằm trong config file

[[drives]]
id = "drive-home"
label = "Ổ nhà"
volume_uuid = "A1B2C3D4-..."
registered_at = 2026-03-05

[[drives]]
id = "drive-office"
label = "Ổ công ty"
volume_uuid = "E5F6G7H8-..."
registered_at = 2026-03-05
```

**Flow khi cắm ổ:**
```
Cắm ổ → DiskArbitration detect
      → Lấy UUID
      → Tìm trong registry
      ├─ Có → sync bình thường
      └─ Không có → KHÔNG sync, notification yêu cầu register
```

**Rules:**
- Không giới hạn số lượng ổ
- 2 ổ trùng UUID → bắt buộc format lại 1 ổ
- Unregister có option `--wipe` xóa data trên ổ, KHÔNG xóa cloud
- Volume UUID lấy qua DiskArbitration framework

## Config

```toml
[drive]
volume_name = "ZORRO"
mount_path = "/Volumes/ZORRO"
symlink = "~/Drive"

[google]
remote = "gdrive"
folder = "DriveSync"

[sync]
debounce_seconds = 30
periodic_minutes = 15
exclude = [
    ".DS_Store", ".Spotlight-V100", ".Trashes",
    ".fseventsd", "._*", "*.tmp", "~$*",
]

[bandwidth]
upload_limit = "0"
download_limit = "0"
```

## Sync Flow

1. **Cắm ổ** → DiskArbitration detect mount
2. **Tạo symlink** ~/Drive → /Volumes/ZORRO
3. **Full bisync** với Google Drive
4. **FSEvents monitor** → file đổi → debounce 30s → sync
5. **Mỗi 15 phút** → bisync toàn bộ (catch thay đổi từ Google Drive)
6. **Rút ổ** → stop watcher, xóa symlink

## State Machine

```
     IDLE ──(mount)──→ SYNCING ──(done)──→ WATCHING
                          │                    │
                       (error)          (file change)
                          │                    │
                       RETRYING        DEBOUNCING(30s)
                          │                    │
                          └──────→ SYNCING ◄───┘

     Any state ──(unmount)──→ IDLE
```

## Menubar & UI

Xem [UI_DESIGN.md](./UI_DESIGN.md)

## CLI

```bash
drivesync setup          # wizard: cài rclone, login Google, test
drivesync status         # trạng thái
drivesync sync           # force sync
drivesync pause/resume   # tạm dừng / tiếp tục
drivesync eject          # sync + eject an toàn
drivesync log            # xem log
drivesync doctor         # diagnose issues
```

## Edge Cases

| Tình huống | Xử lý |
|------------|--------|
| Không có mạng | Queue, sync khi có mạng |
| File conflict | Giữ cả 2: `file.txt` + `file.txt.conflict-YYYYMMDD` |
| Rút ổ giữa sync | rclone atomic write, resume next mount |
| File lớn >1GB | Chunked upload, resume được |
| Google Drive >90% | Notification cảnh báo |
| App crash | Login Items auto-restart |

## Development — Feature Slices

### Slice 0: Foundation
- [ ] Swift app skeleton + menubar icon 💤
- [ ] rclone dependency check
- [ ] Core library structure + XCTest setup
- [ ] CLI argument parsing

### Slice 1: Cắm ổ → sync (core value)
- [ ] Core: MountDetector (DiskArbitration)
- [ ] Core: SyncEngine (gọi rclone bisync)
- [ ] Core: symlink ~/Drive
- [ ] CLI: `drivesync sync`, `drivesync status`
- [ ] Menubar: icon 💤 → 🔄 → ✅
- [ ] Test: mount mock → verify sync called

### Slice 2: Làm việc → auto sync
- [ ] Core: FileWatcher (FSEvents + debounce 30s)
- [ ] Core: periodic sync (Timer 15 min)
- [ ] CLI: verify file change → sync triggered
- [ ] Test: file change → assert sync after debounce

### Slice 3: Xem trạng thái
- [ ] Menubar: dropdown panel (last sync, files pending, progress)
- [ ] CLI: `drivesync log`
- [ ] Core: logging

### Slice 4: Điều khiển
- [ ] Core: pause/resume state
- [ ] Menubar: Sync Now, Pause, Resume, Safe Eject
- [ ] CLI: `drivesync pause`, `drivesync resume`, `drivesync eject`
- [ ] Test: pause → file change → no sync → resume → sync

### Slice 5: Xử lý lỗi
- [ ] Core: offline queue
- [ ] Core: conflict resolution
- [ ] Core: retry logic
- [ ] Menubar: ⚠️ icon + notification
- [ ] CLI: `drivesync doctor`
- [ ] Test: network off → queue → network on → sync

## Future (v2+)

- Nhiều profile, nhiều folder, nhiều mục đích
- Encryption (rclone crypt)
- Selective sync
- Multi cloud
