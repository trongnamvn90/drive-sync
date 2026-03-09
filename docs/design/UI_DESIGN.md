# DriveSync — UX/UI Design

## Menubar Icon States

| State | Icon | Khi nào |
|-------|------|---------|
| Idle | 💤 | Không có ổ cắm |
| Syncing | 🔄 | Đang sync |
| Up-to-date | ✅ | Sync xong, đang watch |
| Paused | ⏸ | User tạm dừng |
| Warning | ⚠️ | Không thể sync nhưng **không có file pending** |
| Error | ❌ | Không thể sync **và có file pending** |

Warning vs Error:
- ⚠️ = mất mạng, auth lỗi... nhưng không có gì chờ sync → kệ cũng được
- ❌ = có file chưa sync lên cloud → data chưa an toàn, cần chú ý

## Menu Dropdown

```
┌──────────────────────────────┐
│  ✅ Up-to-date               │  ← status
│  Home Drive • Synced 14:32   │  ← ổ nào + last sync
│──────────────────────────────│
│  📂 Open Folder              │  ← open ~/Drive trong Finder
│──────────────────────────────│
│  Sync Now                    │
│  Pause Sync                  │
│──────────────────────────────│
│  Safe Eject                  │
│──────────────────────────────│
│  Drives...                   │  ← Settings → tab Drives
│  Settings...                 │  ← Settings window
│  View Logs                   │  ← Settings → tab App (logs)
│──────────────────────────────│
│  Quit DriveSync              │
└──────────────────────────────┘
```

Khi đang sync, phần header hiện progress:

```
│  🔄 Syncing...               │
│  Home Drive • 3/10 files •45%│
│  ████████░░░░░░ 120MB/260MB  │
```

## Warning States (phần mềm chưa ready)

Không có wizard/onboarding. Phần mềm tự check điều kiện, thiếu gì thì hiện warning trong menu dropdown. User tự xử lý từng mục.

```
┌──────────────────────────────┐
│  ⚠️ Setup Required           │
│──────────────────────────────│
│  ❌ Google Drive not connected│  ← click → mở Settings tab Google Drive
│  ❌ rclone not installed      │  ← click → mở hướng dẫn / tự cài
│  ❌ No drives registered      │  ← click → mở Drives tab
│──────────────────────────────│
│  Settings...                 │
│  Quit DriveSync              │
└──────────────────────────────┘
```

Khi tất cả đã ready → menu chuyển về trạng thái bình thường (💤 Idle, chờ cắm ổ).

Ổ chưa register → im lặng, không notify. User tự vào Drives tab để register khi cần.

## Settings Window

1 window duy nhất, 4 tab. Menu dropdown là shortcut đến tab tương ứng.

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  (selected tab content)                   │
│                                           │
└───────────────────────────────────────────┘
```

Menu mapping:
- `Drives...` → mở Settings, tab Drives
- `Settings...` → mở Settings, tab đang chọn lần trước
- `View Logs` → mở Settings, tab App (phần logs)

### Tab: Google Drive

Connected:
```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  Status:  ✅ Connected                    │
│  Account: zorro@gmail.com                 │
│  Storage: 12GB / 15GB                     │
│           [████████████░░░] 80%           │
│           ↑ progress bar, đỏ khi >90%     │
│                                           │
│  Folder:  [ DriveSync       ]             │
│                                           │
│  [Re-login]         [Disconnect]          │
│  ↑ Disconnect hiện confirm alert trước    │
│                                           │
│  Bandwidth                                │
│  Upload:   [  0  ] KB/s  (0 = unlimited) │
│  Download: [  0  ] KB/s  (0 = unlimited) │
│                                           │
└───────────────────────────────────────────┘
```

Chi tiết hành vi: [PRD-001](./PRD-001_Google_Drive_Connection.md)

Chưa login:
```
│  Status: ❌ Not connected                 │
│  [Connect Google Drive]                   │
```

Đang kết nối (chờ OAuth):
```
│  Status: 🔄 Waiting for Google...         │
│  A browser window should have opened.     │
│  Sign in with your Google account         │
│  to continue.                             │
│  [Cancel]                                 │
```
- Timeout 120s → tự chuyển về "Not connected" + hiện lỗi inline

Disconnect confirm alert:
```
┌─────────────────────────────────────────┐
│  Disconnect Google Drive?               │
│                                         │
│  Token will be revoked. You'll need     │
│  to re-connect to sync.                 │
│                                         │
│  [Cancel]              [Disconnect]     │
└─────────────────────────────────────────┘
```

Error messages (hiện inline dưới Status row):

| Lỗi | Message |
|-----|---------|
| Timeout 120s | "Connection timed out. Please try again." |
| Không có mạng | "No internet connection." |
| OAuth bị từ chối | "Access denied. Please try again." |
| Token refresh fail | "Session expired. Please re-connect." |

Hành vi:
- Google Docs/Sheets/Slides → download dạng link file (.gdoc, .gsheet, .gslides), không export

### Tab: Drives

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  🟢 Home Drive                [✏️] [Remove]│
│     ZORRO  •  UUID: A1B2...              │
│     exFAT  •  500GB                      │
│     Last sync: 14:32 today               │
│                                           │
│  ⚫ Office Drive              [✏️] [Remove]│
│     ZORRO  •  UUID: E5F6...              │
│     exFAT  •  500GB                      │
│     Last sync: 22:15 yesterday           │
│                                           │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  [+ Register New Drive]                   │
│                                           │
└───────────────────────────────────────────┘
```

- 🟢 = ổ đang cắm, ⚫ = ổ không cắm
- ✏️ = đổi label
- Remove → confirm dialog với checkbox `☐ Wipe data on drive` (mặc định tắt)
- "Register New Drive" → mở dialog đăng ký (xem bên dưới)

### Dialog: Register New Drive

```
┌─────────────────────────────────────────┐
│  Register New Drive                      │
│─────────────────────────────────────────│
│                                         │
│  Select drive:                           │
│  ○ 💾 ZORRO  •  exFAT  •  500GB        │
│       UUID: A1B2C3D4...                  │
│  ● 💾 BACKUP  •  APFS  •  1TB          │
│       UUID: X9Y8Z7W6...                  │
│                                         │
│  Label: [ Office Drive        ]         │
│                                         │
│  ☐ Format drive before registering       │
│    (bật → hiện: volume name, filesystem) │
│                                         │
│─────────────────────────────────────────│
│  (Warnings — thay đổi theo tình huống)  │
│─────────────────────────────────────────│
│  [Register]             [Cancel]        │
└─────────────────────────────────────────┘
```

Không có ổ nào cắm:
```
│  No external drives found.              │
│  Plug in a drive and press [Refresh]    │
```

Chỉ 1 ổ → chọn sẵn, không cần bấm.

**Format options** (khi bật checkbox):
- Volume name: text field
- Filesystem: exFAT (cross-platform) / APFS (macOS only)

**Warnings area** — thay đổi theo context:

| Tình huống | Warning |
|------------|---------|
| Ổ trống + Cloud trống | (không hiện) |
| Ổ trống + Cloud có data | ℹ️ Cloud has 12GB → will pull to drive |
| Ổ có data + Cloud trống | ℹ️ Drive has 8GB → will push to cloud |
| Cả hai có data | ⚠️ Choose sync method: Merge both / Cloud wins / Drive wins |
| Format bật | ⚠️ ALL DATA ON DRIVE WILL BE ERASED! (+ thông báo cloud nếu có) |

Case 1-3: phần mềm tự xử lý sau đăng ký. Case 4: bắt buộc user chọn.
Format bật → ổ luôn trống → chỉ rơi vào case 1 hoặc 2.

**Confirm popup** — hiện thêm 1 bước xác nhận khi:
- Format bật (xóa data)
- Case 4 (cả hai có data — bất kể chọn Merge, Cloud wins hay Drive wins)

```
┌─────────────────────────────────────────┐
│  ⚠️ Confirm                             │
│                                         │
│  (summary of what will happen)          │
│                                         │
│  [Confirm]              [Go Back]       │
└─────────────────────────────────────────┘
```

Không hiện confirm khi case 1-3 không format (an toàn, không mất data).

**Trùng UUID** — chọn ổ có UUID đã tồn tại trong registry → block, không cho đăng ký:
```
│  ⚠️ Warnings                            │
│  • UUID matches registered "Home Drive"  │
│  • Format drive to generate new UUID,    │
│    or remove old drive in Drives tab     │
│                                         │
│  [Register] (disabled)    [Cancel]      │
```
Bật checkbox Format → sau format UUID mới → hết trùng → enable nút Register.

### Tab: Sync

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  Debounce:       [ 30 ] sec    (5-300)   │
│  Periodic sync:  [ 15 ] min    (5-60)    │
│                                           │
│  On file delete: [ Move to Trash ▾]      │
│                  - Move to Trash          │
│                  - Delete permanently     │
│                                           │
└───────────────────────────────────────────┘
```

- Exclude list (.DS_Store, .Spotlight-V100, ...) hardcode trong app, không hiện trong UI
- Mặc định Move to Trash (an toàn hơn)

### Tab: App

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  ☑ Launch at Login                        │
│  ☑ Notifications                          │
│                                           │
│  Symlink: [ ~/Drive          ]            │
│                                           │
│  Log level: [ info       ▾]              │
│  Keep logs: [ 30 ] days                   │
│                                           │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  Logs (live)                    [⏸ Pause] │
│  ┌───────────────────────────────────┐    │
│  │ 14:32 ✅ Sync complete (3 files)  │    │
│  │ 14:30 🔄 Sync started             │    │
│  │ 14:15 ✅ Periodic sync OK         │    │
│  │ 13:45 📂 File changed: report.doc│    │
│  └───────────────────────────────────┘    │
│  [Open Log File]                          │
│                                           │
└───────────────────────────────────────────┘
```

- Logs auto-refresh (live stream), nút Pause để dừng scroll khi đọc lại
- `View Logs` trong menu dropdown → mở Settings tab App, scroll đến phần logs

### About Window

Nằm ở menu bar native: DriveSync → About DriveSync. Window riêng theo chuẩn macOS.

```
┌─────────────────────────────────┐
│                                 │
│         [App Icon Logo]         │
│                                 │
│         DriveSync               │
│         Version 1.0.0           │
│                                 │
│  rclone: v1.68.0                │
│  macOS: 15.3                    │
│                                 │
│  © 2026 Zorro                   │
│  github.com/zorro/drive-sync    │
│                                 │
│  [Licenses]                     │
│                                 │
└─────────────────────────────────┘
```

Bấm Licenses → panel hiện danh sách open source dependencies:
- Mỗi item: tên, license type, link repo
- Bấm vào → mở full license text
- Auto generate từ dependencies khi build

## Icon Spec

### App Icon

- Master: 1024x1024px, macOS tự scale xuống 512, 256, 128, 64, 32, 16
- Format: PNG hoặc SVG
- Style: macOS Big Sur+ (3D-lite, gradient nhẹ, có depth/shadow)
- Concept: ổ cứng portable (nhìn nghiêng 3/4) + 2 mũi tên sync xoay vòng + hint đám mây nhỏ phía trên
- Color palette:
  - Primary: xanh dương (#2196F3 hoặc #1E88E5)
  - Ổ cứng: xám bạc metallic gradient
  - Sync arrows: trắng hoặc xanh nhạt
  - Cloud: trắng mờ

### Menubar Icons (6 states)

- Thiết kế ở size lớn (256x256 hoặc SVG), export ra: 18x18 (@1x), 36x36 (@2x), 54x54 (@3x)
- **Bắt buộc monochrome** (template image) — macOS tự đổi màu theo dark/light mode
- Format: PDF hoặc PNG
- Style: line icon, stroke 1.5-2px
- Base shape: ổ cứng portable đơn giản (hình chữ nhật bo góc)
- State indicator: badge overlay góc phải dưới, chồng lên ổ cứng, chiếm **25-30%** kích thước icon

Quy trình thiết kế:
1. Thiết kế 1 **base icon** (ổ cứng, không badge)
2. Thiết kế 6 **badge** riêng biệt
3. Composite: base + badge → 6 menubar icons

| State | Badge (góc phải dưới, 25-30%) |
|-------|-------------------------------|
| Idle | gạch ngang (—) hoặc không có badge |
| Syncing | 2 mũi tên xoay (↻), animate rotate |
| Up-to-date | checkmark (✓) |
| Paused | 2 gạch đứng (⏸) |
| Warning | tam giác (△) |
| Error | dấu x (✕) |

### In-app Icons

Dùng SF Symbols (Apple native), không cần thiết kế custom.

## Chưa giải quyết

- **Cắm 2 ổ cùng lúc**: chưa rõ nên hiển thị và xử lý thế nào. Tạm thời không support, bàn sau.
- **Team Drive**: rclone support được nhưng conflict phức tạp hơn. Để v2+.
- **Google Docs export**: hiện chỉ download dạng link file. Cần workaround cho offline access sau.

---

**Author:** Claude (Minh Thư) — 2026-03-05
