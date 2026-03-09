# PRD-003: Settings (Sync + App)

## Mục tiêu

User cấu hình hành vi sync và app từ tab "Sync" và "App" trong Settings. Mọi thay đổi persist ngay vào `config.toml`. Hai tab gộp chung PRD vì cùng pattern: UI fields → didSet → ConfigManager → file.

## Scope

| Trong scope | Ngoài scope |
|-------------|-------------|
| Sync tab: debounce, periodic, on_delete | SyncEngine implementation (PRD riêng) |
| App tab: launch at login, notifications, symlink, log level, keep logs | FSEvents / file watcher logic |
| App tab: live logs viewer (read-only) | rclone command building (PRD-002) |
| Validation + clamping giá trị | CLI `drivesync setup` command |
| Persist vào config.toml | LaunchAgent cho launch-at-login |

---

## Tab Sync — Settings

### 1. Debounce (giây)

Khi FSEvents phát hiện file thay đổi, đợi `debounce_sec` giây trước khi trigger sync. Tránh sync liên tục khi user đang edit file.

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[sync] debounce_sec` |
| Default | `30` |
| Range | `5–300` |
| UI | TextField (number) + "sec" + hint `(5–300)` |

**Hành vi:**
- Mỗi file change event reset debounce timer
- Khi timer hết → trigger incremental sync
- Giá trị ngoài range → clamp về min/max khi SyncEngine đọc

### 2. Periodic Sync (phút)

Full bisync chạy định kỳ để bắt thay đổi từ phía Google Drive (Google Drive không push được).

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[sync] periodic_sync_min` |
| Default | `15` |
| Range | `5–60` |
| UI | TextField (number) + "min" + hint `(5–60)` |

**Hành vi:**
- Timer chạy từ lúc mount drive, reset sau mỗi lần sync hoàn tất
- Chạy `rclone bisync` full (không phải incremental)
- Nếu đang sync → skip, đợi periodic tiếp theo

### 3. On File Delete

Khi sync phát hiện file bị xóa ở một phía, phía còn lại xử lý thế nào.

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[sync] on_delete` |
| Default | `"Move to Trash"` |
| Options | `"Move to Trash"`, `"Delete permanently"` |
| UI | Picker dropdown |

**Hành vi:**
- **Move to Trash**: move vào Trash thay vì xóa. User có thể recover.
- **Delete permanently**: xóa thẳng, không recovery. rclone default behavior.

---

## Tab App — Settings

### 4. Launch at Login

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[app] launch_at_login` |
| Default | `true` |
| UI | Toggle |

**Hành vi:**
- `true` → đăng ký LaunchAgent (hoặc `SMAppService.register()` trên macOS 13+)
- `false` → hủy đăng ký
- Implementation chi tiết ngoài scope PRD này — chỉ lưu preference

### 5. Notifications

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[app] show_notifications` |
| Default | `true` |
| UI | Toggle |

**Hành vi:**
- `true` → hiện macOS notification khi: sync complete, sync error, drive mount/unmount
- `false` → tắt hết notification
- Dùng `UserNotifications` framework

### 6. Symlink Path

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[app] symlink_path` |
| Default | `"~/Drive"` |
| UI | TextField, width 200pt |

**Hành vi:**
- Khi drive mount → tạo symlink từ path này đến `/Volumes/ZORRO`
- Khi drive unmount → xóa symlink
- Path expand `~` thành home directory
- Nếu path đã tồn tại (không phải symlink) → báo lỗi, không overwrite

### 7. Log Level

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[app] log_level` |
| Default | `"info"` |
| Options | `"debug"`, `"info"`, `"warn"`, `"error"` |
| UI | Picker dropdown, width 200pt |

**Hành vi:**
- Ảnh hưởng đến mức độ chi tiết ghi log file
- `debug` → ghi tất cả, bao gồm rclone stdout
- `info` → sync events, mount/unmount
- `warn` → chỉ cảnh báo và lỗi
- `error` → chỉ lỗi

### 8. Keep Logs (ngày)

| Thuộc tính | Giá trị |
|------------|---------|
| Key | `[app] keep_logs_days` |
| Default | `30` |
| Range | `1–365` |
| UI | TextField (number) + "days" |

**Hành vi:**
- Log files cũ hơn X ngày bị xóa tự động khi app khởi động
- Log dir: `~/.config/drivesync/logs/`

### 9. Live Logs Viewer (read-only)

Phần dưới tab App hiển thị log entries realtime.

**UI:**
- Header: "Logs (live)" headline + Pause/Resume button
- ScrollView monospace text, height 120pt, dark background
- Mỗi entry: `[time] [icon] message`
- Button "Open Log File" → mở log file trong default text editor

**Hành vi:**
- Stream log entries từ LogManager (khi implement)
- Pause: ngừng auto-scroll, giữ nguyên vị trí
- Resume: tiếp tục auto-scroll đến bottom
- Hiện tại: mock data, sẽ wire vào LogManager sau

---

## Config Format

```toml
[sync]
debounce_sec = 30
periodic_sync_min = 15
on_delete = "Move to Trash"

[app]
launch_at_login = true
show_notifications = true
symlink_path = "~/Drive"
log_level = "info"
keep_logs_days = 30
```

File: `~/.config/drivesync/config.toml`

## Persistence

- Mỗi field dùng `didSet` trên AppState property → `ConfigManager.set()` → ghi file ngay
- App khởi động → `ConfigManager` load từ file → AppState init với giá trị đã lưu (hoặc default)
- **Đã implement xong** (ConfigManager + AppState wiring)

## UI Spec

### Sync Tab

```
┌───────────────────────────────────────────┐
│  🔄 Sync (sidebar tab)                    │
│───────────────────────────────────────────│
│                                           │
│  ┌─ Section: Timing ─────────────────┐   │
│  │ Debounce:      [ 30 ] sec         │   │
│  │                (5–300) ← caption   │   │
│  │ Periodic sync: [ 15 ] min         │   │
│  │                (5–60) ← caption    │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section: File Deletion ──────────┐   │
│  │ On file delete: [Move to Trash ▾] │   │
│  └────────────────────────────────────┘   │
│                                           │
└───────────────────────────────────────────┘
```

### App Tab

```
┌───────────────────────────────────────────┐
│  ⚙ App (sidebar tab)                      │
│───────────────────────────────────────────│
│                                           │
│  ┌─ Section ─────────────────────────┐   │
│  │ [✓] Launch at Login               │   │
│  │ [✓] Notifications                 │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section ─────────────────────────┐   │
│  │ Symlink: [ ~/Drive           ]    │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section ─────────────────────────┐   │
│  │ Log level: [ info ▾ ]            │   │
│  │ Keep logs: [ 30 ] days           │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ─────────────────────────────────────    │
│  Logs (live)              [⏸ Pause]      │
│  ┌─────────────────────────────────┐     │
│  │ 14:32  ✓  Sync complete (3)    │     │
│  │ 14:30  ↻  Sync started         │     │
│  │ 14:15  ✓  Periodic sync OK     │     │
│  │ 13:45  📄 File changed: ...    │     │
│  └─────────────────────────────────┘     │
│  [Open Log File]                          │
│                                           │
└───────────────────────────────────────────┘
```

## Implementation Status

| Item | Status |
|------|--------|
| Sync tab UI | ✅ Done |
| App tab UI | ✅ Done |
| Persist tất cả settings vào config.toml | ✅ Done |
| Load settings khi app khởi động | ✅ Done |
| Validation (clamp min/max) | ⏭️ Deferred — PRD-004 dùng Stepper enforce range, SyncEngine clamp khi đọc |
| Launch at login (SMAppService) | ✅ Done — register/unregister on toggle |
| Notifications (UserNotifications) | ✅ Done — permission request + sendNotification() helper |
| Live logs wire vào LogManager | ⏭️ Deferred — cần LogManager (Slice 3) |
| Open Log File button | ✅ Done — opens latest log or log directory |

## Validation Rules

UI không block input. SyncEngine clamp khi đọc:

```swift
let debounce = max(5, min(300, config.int(section: "sync", key: "debounce_sec") ?? 30))
let periodic = max(5, min(60, config.int(section: "sync", key: "periodic_sync_min") ?? 15))
let keepLogs = max(1, min(365, config.int(section: "app", key: "keep_logs_days") ?? 30))
```

## Acceptance Criteria

- [ ] Sync tab: thay đổi debounce → persist ngay vào config.toml
- [ ] Sync tab: thay đổi periodic sync → persist ngay
- [ ] Sync tab: thay đổi on_delete → persist ngay
- [ ] App tab: thay đổi launch_at_login → persist ngay
- [ ] App tab: thay đổi show_notifications → persist ngay
- [ ] App tab: thay đổi symlink_path → persist ngay
- [ ] App tab: thay đổi log_level → persist ngay
- [ ] App tab: thay đổi keep_logs_days → persist ngay
- [ ] Tắt app mở lại → tất cả giá trị giữ nguyên
- [ ] Chưa có config.toml → dùng default values
- [ ] Live logs hiển thị entries (mock data OK cho MVP)

---

## ✅ Implementation Status

**Fully implemented** — 2026-03-07

| Item | Status |
|------|--------|
| Sync tab UI (Stepper debounce, periodic, Picker on_delete) | ✅ Done |
| App tab UI (toggles, symlink, log level, keep logs) | ✅ Done |
| Persist all settings → config.toml via didSet | ✅ Done |
| Load settings on app startup | ✅ Done |
| Launch at Login (SMAppService) | ✅ Done |
| Notifications (UserNotifications permission + helper) | ✅ Done |
| Open Log File button | ✅ Done |
| Live logs wired to LogManager AsyncStream | ✅ Done (PRD-005) |
| Validation clamp (SyncEngine reads) | ⏭️ Deferred — needs SyncEngine (PRD-002) |

---

**Author:** Claude (Minh Thư) — 2026-03-07
