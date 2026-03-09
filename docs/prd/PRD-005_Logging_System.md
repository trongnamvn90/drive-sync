# PRD-005: Logging System

## Mục tiêu

Xây dựng `LogManager` — hệ thống ghi log trung tâm của DriveSync. Mọi event quan trọng trong app đều đi qua `LogManager`: ghi file theo ngày, filter theo log level, stream realtime lên UI. Thay thế mock data trong `AppTab` bằng log entries thật. Dọn dẹp log cũ tự động khi app khởi động.

## Scope

| Trong scope | Ngoài scope |
|-------------|-------------|
| `LogManager` actor — ghi file + stream realtime | Mount/unmount events (chưa implement) |
| Log file theo ngày: `drivesync-YYYY-MM-DD.log` | Sync events, rclone output (PRD-002) |
| Log format: `[HH:mm:ss] [LEVEL] message` | FSEvents / file watcher events |
| Filter theo `log_level` từ config | CLI log command |
| Cleanup log files cũ hơn `keep_logs_days` | Log rotation trong cùng một ngày |
| `AsyncStream<LogEntry>` cho live UI | Push notification khi có error |
| Wire vào: app start/quit, OAuth events, settings changes | Crash reporting / Sentry |
| `Open Log File` mở đúng file hôm nay | |
| Pause/Resume live log stream trong UI | |

---

## 1. LogManager — Actor

### Tổng quan

`LogManager` là `actor` singleton, thread-safe. Là điểm duy nhất để ghi log trong toàn bộ app. Không class nào tự ghi file log — phải gọi qua `LogManager`.

```swift
actor LogManager {
    static let shared = LogManager()
}
```

### API công khai

```swift
// Ghi log
func log(_ level: LogLevel, _ message: String)

// Convenience methods
func debug(_ message: String)
func info(_ message: String)
func warn(_ message: String)
func error(_ message: String)

// Stream realtime cho UI
func makeStream() -> AsyncStream<LogEntry>

// Dọn log cũ — gọi khi app khởi động
func deleteOldLogs(keepDays: Int) async

// Mở log file hôm nay
func openTodayLogFile()
```

### Log Level

```swift
enum LogLevel: String, Comparable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    // So sánh để filter: .info >= .info → true, .debug >= .info → false
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { ... }
}
```

Filter logic: chỉ ghi log khi `entryLevel >= configuredMinLevel`. Ví dụ config `log_level = "warn"` → chỉ ghi `warn` và `error`, bỏ qua `debug` và `info`.

---

## 2. Log File Format

### Vị trí

```
~/.config/drivesync/logs/drivesync-YYYY-MM-DD.log
```

Ví dụ: `~/.config/drivesync/logs/drivesync-2026-03-09.log`

- Một file mỗi ngày. Ngày mới → file mới tự động.
- `LogManager` tự tạo thư mục `logs/` nếu chưa có.
- Append-only — không truncate file cũ trong cùng ngày.

### Entry Format

```
[HH:mm:ss] [LEVEL] message
```

Ví dụ:

```
[09:15:00] [INFO]  DriveSync started (v1.0.0)
[09:15:01] [INFO]  Loaded auth token for user@gmail.com
[09:15:02] [DEBUG] Token expires at 2026-03-09T10:15:01Z
[09:30:44] [INFO]  Google OAuth connected: user@gmail.com
[09:31:00] [INFO]  Settings changed: log_level = "debug"
[09:45:12] [WARN]  Token refresh failed: network timeout, retrying...
[09:45:15] [INFO]  Token refreshed successfully
[10:00:00] [ERROR] Google OAuth error: invalid_grant
[10:02:33] [INFO]  Google OAuth disconnected
[10:02:34] [INFO]  Google OAuth re-login initiated
[18:30:00] [INFO]  DriveSync shutting down
```

**Padding:** `[LEVEL]` được pad để canh hàng — `INFO` và `WARN` thêm 1 space sau. Xem ví dụ trên.

### LogEntry struct (updated)

Cập nhật `LogEntry` trong `AppState.swift` để phù hợp với data thật:

```swift
struct LogEntry: Identifiable {
    let id    = UUID()
    let time  : String   // "HH:mm:ss"
    let level : LogLevel
    let message: String

    // Icon cho UI — dựa theo level
    var icon: String {
        switch level {
        case .debug: return "ant"
        case .info:  return "info.circle"
        case .warn:  return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}
```

---

## 3. Buffering & Ghi File

### Internal Buffer

`LogManager` dùng in-memory buffer để:
1. Tránh ghi disk mỗi lần một entry (tốn I/O)
2. Flush theo batch khi buffer đủ lớn hoặc sau interval

```
Buffer size  : 20 entries  → flush khi đầy
Flush interval: 5 giây     → flush định kỳ dù chưa đầy
App shutdown  : flush ngay lập tức (đồng bộ)
```

### Ghi file

- Append vào file hôm nay (`drivesync-YYYY-MM-DD.log`)
- Mỗi entry một dòng, kết thúc `\n`
- Encoding: UTF-8
- Nếu ghi file thất bại (disk full, permissions) → print ra stderr, không crash app

---

## 4. Cleanup Log Cũ

Khi app khởi động, `LogManager.deleteOldLogs(keepDays:)` được gọi một lần.

**Logic:**
- Liệt kê tất cả file trong `~/.config/drivesync/logs/`
- Parse ngày từ tên file: `drivesync-YYYY-MM-DD.log`
- File có ngày cũ hơn `today - keepDays` → xóa
- File không match pattern tên → bỏ qua, không xóa
- Nếu `keepDays = 30` và hôm nay `2026-03-09` → giữ từ `2026-02-08` trở đi, xóa trước đó

**Ghi log sau cleanup:**

```
[INFO]  Log cleanup: deleted 3 file(s) older than 30 days
```

Nếu không có file nào bị xóa → không ghi dòng này (tránh noise).

---

## 5. AsyncStream cho Live UI

### Stream

```swift
// AppTab subscribe khi view appear
let stream = await LogManager.shared.makeStream()
for await entry in stream {
    // update UI
}
```

- `makeStream()` trả về `AsyncStream<LogEntry>`
- `LogManager` giữ list các `AsyncStream.Continuation`
- Mỗi lần `log()` được gọi (và entry vượt filter) → gửi entry tới tất cả continuations
- Khi view disappear → cancel stream (continuation tự cleanup qua `onTermination`)

### Buffer khởi tạo stream

Khi UI vừa mở (ví dụ user lần đầu vào tab App), stream cần hiển thị các entries gần nhất. `LogManager` giữ một ring buffer 100 entries gần nhất trong memory. Khi tạo stream mới → replay 100 entries đó trước, rồi tiếp tục nhận realtime.

---

## 6. Pause/Resume trong UI

`AppTab` giữ state `@State private var logsPaused = false`.

**Pause:**
- User bấm "⏸ Pause"
- UI ngừng append entries mới vào `displayedEntries`
- Stream vẫn chạy ở background (để không mất entries)
- `LogManager` stream vẫn emit → UI buffer local nhưng không render

**Resume:**
- User bấm "▶ Resume"
- UI append tất cả entries đã buffer trong thời gian pause
- Scroll to bottom
- Tiếp tục render realtime

**Implementation pattern trong AppTab:**

```swift
@State private var logsPaused = false
@State private var displayedEntries: [LogEntry] = []
@State private var pauseBuffer: [LogEntry] = []
```

Khi `logsPaused = true` → append vào `pauseBuffer`.
Khi resume → `displayedEntries += pauseBuffer`, clear `pauseBuffer`, scroll to bottom.

---

## 7. Open Log File

`AppState.openLogFile()` hiện tại mở file mới nhất hoặc thư mục. Cập nhật lại để luôn mở **file hôm nay**:

```swift
func openLogFile() {
    let today = LogManager.todayLogFileURL()
    // Tạo file nếu chưa có (empty)
    if !FileManager.default.fileExists(atPath: today.path) {
        FileManager.default.createFile(atPath: today.path, contents: nil)
    }
    NSWorkspace.shared.open(today)
}
```

`LogManager` expose static helper:

```swift
static func todayLogFileURL() -> URL {
    let dateStr = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: .withFullDate)
    return logDirectory.appendingPathComponent("drivesync-\(dateStr).log")
}
```

---

## 8. Wire vào Các Feature Đang Hoạt Động

### 8.1 App Startup

Trong `DriveSync.swift` (hoặc `AppDelegate`) — ngay sau khi app khởi động:

```
[INFO]  DriveSync started (v<version>)
```

Sau đó gọi cleanup:

```swift
await LogManager.shared.deleteOldLogs(keepDays: appState.keepLogsDays)
```

### 8.2 App Shutdown

Dùng `onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))`:

```
[INFO]  DriveSync shutting down
```

Flush buffer đồng bộ trước khi process exit.

### 8.3 Google OAuth — Connect

Trong `AppState.connectGoogle()`:

| Event | Log |
|-------|-----|
| Bắt đầu connect | `[INFO] Google OAuth connecting...` |
| Connect thành công | `[INFO] Google OAuth connected: <email>` |
| User cancel | `[INFO] Google OAuth cancelled by user` |
| Lỗi known (`GoogleAuthError`) | `[ERROR] Google OAuth error: <userMessage>` |
| Lỗi unknown | `[ERROR] Google OAuth error: <error.localizedDescription>` |

### 8.4 Google OAuth — Disconnect

Trong `AppState.disconnectGoogle()`:

```
[INFO]  Google OAuth disconnected
```

### 8.5 Google OAuth — Re-login

Trong `AppState.reloginGoogle()`:

```
[INFO]  Google OAuth re-login initiated
```

(Sau đó các log của connect flow sẽ tiếp tục.)

### 8.6 Google OAuth — Load on Startup

Trong `AppState.loadSavedAuth()`:

| Event | Log |
|-------|-----|
| Token load thành công | `[INFO] Loaded saved auth: <email>` |
| Không có token | (không log — silent OK) |
| Load thất bại | `[WARN] Failed to load saved auth: <error>` |

### 8.7 Google OAuth — Token Refresh

Trong `GoogleAuthService` hoặc `TokenManager`:

| Event | Log |
|-------|-----|
| Refresh bắt đầu | `[DEBUG] Refreshing access token...` |
| Refresh thành công | `[INFO]  Token refreshed successfully` |
| Refresh thất bại | `[WARN]  Token refresh failed: <error>` |

### 8.8 Settings Changes

Trong các `didSet` của `AppState` — log khi user thay đổi setting. Chỉ log những setting user có thể thay đổi thủ công (không log internal state):

| Setting thay đổi | Log |
|-----------------|-----|
| `logLevel` | `[INFO] Settings changed: log_level = "<value>"` |
| `keepLogsDays` | `[INFO] Settings changed: keep_logs_days = <value>` |
| `launchAtLogin` | `[INFO] Settings changed: launch_at_login = <value>` |
| `showNotifications` | `[INFO] Settings changed: show_notifications = <value>` |
| `symlinkPath` | `[INFO] Settings changed: symlink_path = "<value>"` |
| `googleFolder` | `[INFO] Settings changed: google.folder = "<value>"` |
| `uploadLimit` | `[INFO] Settings changed: upload_limit = <value>` |
| `downloadLimit` | `[INFO] Settings changed: download_limit = <value>` |
| `debounceSec` | `[INFO] Settings changed: debounce_sec = <value>` |
| `periodicSyncMin` | `[INFO] Settings changed: periodic_sync_min = <value>` |
| `onDeleteAction` | `[INFO] Settings changed: on_delete = "<value>"` |

**Lưu ý:** Log settings change dùng level `INFO` — không phải `DEBUG` vì đây là action của user, cần trace khi debug config issues.

---

## 9. LogLevel — Lấy từ Config

`LogManager` cần đọc `log_level` từ `ConfigManager` mỗi khi gọi `log()`. Vì user có thể thay đổi level trong runtime:

```swift
private func currentMinLevel() -> LogLevel {
    let raw = ConfigManager.shared.string(section: "app", key: "log_level") ?? "info"
    return LogLevel(rawValue: raw.uppercased()) ?? .info
}
```

Không cache — đọc fresh mỗi lần để reflect thay đổi tức thì khi user đổi log level trong UI.

---

## Config Format (không thay đổi)

Config đã có sẵn, không thêm key mới:

```toml
[app]
log_level = "info"      # debug | info | warn | error
keep_logs_days = 30     # 1–365
```

File: `~/.config/drivesync/config.toml`

---

## UI Spec

### Live Logs — AppTab (updated)

```
┌───────────────────────────────────────────────┐
│  ⚙ App (sidebar tab)                          │
│───────────────────────────────────────────────│
│  [Form sections: Launch/Notif/Symlink/Log...] │
│                                               │
│  ─────────────────────────────────────────    │
│  Logs (live)                  [⏸ Pause]      │
│  ┌─────────────────────────────────────────┐  │
│  │ 09:15:00  ⓘ  DriveSync started        │  │
│  │ 09:15:01  ⓘ  Loaded saved auth: u@g.. │  │
│  │ 09:30:44  ⓘ  Google OAuth connected   │  │
│  │ 09:31:00  ⓘ  Settings changed: log_..│  │
│  │ 09:45:12  ⚠  Token refresh failed     │  │  ← warn: màu vàng
│  │ 09:45:15  ⓘ  Token refreshed OK       │  │
│  │ 10:00:00  ✕  Google OAuth error: ...  │  │  ← error: màu đỏ
│  └─────────────────────────────────────────┘  │
│  [Open Log File]                              │
│                                               │
└───────────────────────────────────────────────┘
```

**Color coding theo level:**
- `debug` → `.secondary` (gray)
- `info` → `.primary` (default)
- `warn` → `.orange`
- `error` → `.red`

**Auto-scroll:** ScrollView tự scroll đến bottom khi có entry mới (trừ khi đang pause).

---

## Implementation Details

### Khởi tạo trong App Entry Point

```swift
// DriveSync.swift (App struct) hoặc AppDelegate
.task {
    // 1. Log startup
    await LogManager.shared.info("DriveSync started (v\(appVersion))")

    // 2. Cleanup cũ
    await LogManager.shared.deleteOldLogs(keepDays: appState.keepLogsDays)

    // 3. Load auth (log bên trong loadSavedAuth)
    appState.loadSavedAuth()
}
```

### Actor isolation

`LogManager` là `actor` → mọi call từ `@MainActor` context phải dùng `await`:

```swift
// Trong AppState (MainActor)
await LogManager.shared.info("Google OAuth connected: \(email)")
```

Với `didSet` (synchronous context trên MainActor), dùng `Task`:

```swift
var logLevel: String {
    didSet {
        config.set(section: "app", key: "log_level", value: logLevel)
        Task { await LogManager.shared.info("Settings changed: log_level = \"\(logLevel)\"") }
    }
}
```

### File handle

`LogManager` giữ một `FileHandle` mở cho file hôm nay. Khi ngày thay đổi (app chạy qua midnight):
- Đóng handle cũ
- Mở handle mới cho file ngày mới
- Ghi entry đầu tiên của ngày: `[INFO] --- New log file: drivesync-YYYY-MM-DD.log ---`

---

## Files cần sửa / tạo

### Tạo mới

| File | Mô tả |
|------|-------|
| `Sources/DriveSync/Core/Logging/LogManager.swift` | Actor chính — ghi file, stream, cleanup |
| `Sources/DriveSync/Core/Logging/LogLevel.swift` | Enum `LogLevel` với Comparable |

### Sửa

| File | Thay đổi |
|------|----------|
| `Sources/DriveSync/ViewModels/AppState.swift` | Cập nhật `LogEntry` struct (thêm `level`, xóa `icon`). Thêm `await LogManager.shared.log()` vào các hàm OAuth. Thêm `Task { await LogManager.shared... }` vào mọi `didSet`. Cập nhật `openLogFile()` dùng `LogManager.todayLogFileURL()`. |
| `Sources/DriveSync/Views/Settings/AppTab.swift` | Thay mock data bằng `AsyncStream`. Implement pause buffer logic. Color coding theo level. Auto-scroll to bottom. |
| `Sources/DriveSync/DriveSync.swift` | Gọi `LogManager.shared.info("DriveSync started...")` và `deleteOldLogs()` khi app launch. Gọi flush khi shutdown. |
| `Sources/DriveSync/Core/Auth/GoogleAuthService.swift` | Thêm log cho token refresh (debug/info/warn). |

### Không sửa

- `ConfigManager.swift` — không thay đổi, `LogManager` đọc qua `ConfigManager.shared`
- `Secrets.swift` — không liên quan
- Các file sync/mount (chưa implement)

---

## Acceptance Criteria

### LogManager Core

- [ ] `LogManager.shared` là actor singleton, có thể gọi từ bất kỳ đâu trong app
- [ ] Ghi log vào `~/.config/drivesync/logs/drivesync-YYYY-MM-DD.log`
- [ ] Thư mục `logs/` tự tạo nếu chưa có
- [ ] Entry format đúng: `[HH:mm:ss] [LEVEL] message\n`
- [ ] `WARN` và `INFO` được pad 1 space để canh hàng với `DEBUG` và `ERROR`
- [ ] `debug` entries chỉ ghi khi `log_level = "debug"`
- [ ] `info` entries bị bỏ qua khi `log_level = "warn"` hoặc `"error"`
- [ ] Thay đổi `log_level` trong UI → có hiệu lực ngay lập tức (không cần restart)

### File Rotation & Cleanup

- [ ] App chạy qua midnight → tự mở file mới cho ngày hôm sau
- [ ] `deleteOldLogs(keepDays: 30)` → xóa files có ngày cũ hơn 30 ngày
- [ ] File không match pattern `drivesync-YYYY-MM-DD.log` → không bị xóa
- [ ] Sau cleanup → ghi log số file đã xóa (chỉ khi > 0)

### Buffering

- [ ] Flush buffer khi đạt 20 entries
- [ ] Flush buffer mỗi 5 giây
- [ ] Flush ngay lập tức khi app shutdown (không mất entries cuối)
- [ ] Ghi file thất bại → in stderr, không crash app

### Live Stream

- [ ] `makeStream()` trả về `AsyncStream<LogEntry>`
- [ ] Stream replay 100 entries gần nhất khi khởi tạo
- [ ] Entries mới broadcast tới tất cả active streams
- [ ] Cancel stream (view disappear) → cleanup continuation, không leak

### UI — AppTab

- [ ] Xóa mock data trong `AppState.logEntries`, thay bằng stream từ `LogManager`
- [ ] Live logs hiển thị entries thật theo thứ tự thời gian
- [ ] `warn` entries → màu `.orange`, `error` entries → màu `.red`
- [ ] Auto-scroll to bottom khi có entry mới (khi không pause)
- [ ] Bấm "⏸ Pause" → UI ngừng update, stream vẫn chạy background
- [ ] Bấm "▶ Resume" → append tất cả entries đã buffer khi pause, scroll to bottom
- [ ] "Open Log File" → mở `drivesync-<hôm nay>.log` trong default editor
- [ ] "Open Log File" → nếu file chưa tồn tại → tạo file trống rồi mở

### Wire-in Events

- [ ] App khởi động → `[INFO] DriveSync started (v<version>)`
- [ ] App tắt → `[INFO] DriveSync shutting down`
- [ ] OAuth connect thành công → `[INFO] Google OAuth connected: <email>`
- [ ] OAuth connect lỗi → `[ERROR] Google OAuth error: <message>`
- [ ] OAuth cancel → `[INFO] Google OAuth cancelled by user`
- [ ] OAuth disconnect → `[INFO] Google OAuth disconnected`
- [ ] OAuth re-login → `[INFO] Google OAuth re-login initiated`
- [ ] Load saved auth thành công → `[INFO] Loaded saved auth: <email>`
- [ ] Load saved auth thất bại → `[WARN] Failed to load saved auth: <error>`
- [ ] Token refresh thành công → `[INFO] Token refreshed successfully`
- [ ] Token refresh thất bại → `[WARN] Token refresh failed: <error>`
- [ ] Mỗi settings change → `[INFO] Settings changed: <key> = <value>`

---

## ✅ Implementation Status

**Fully implemented** — 2026-03-09

| Item | Status |
|------|--------|
| LogManager actor singleton | ✅ Done |
| File write with buffer (20 entries / 5s flush) | ✅ Done |
| Log level filtering (reads from ConfigManager) | ✅ Done |
| AsyncStream + ring buffer (100 entries replay) | ✅ Done |
| Log cleanup (deleteOldLogs) | ✅ Done |
| Date rollover (midnight file switch) | ✅ Done |
| Live logs UI in AppTab (stream, pause/resume, color coding) | ✅ Done |
| Open Log File (today's file) | ✅ Done |
| Wire-in: app start/shutdown | ✅ Done |
| Wire-in: OAuth events (connect/disconnect/re-login/refresh) | ✅ Done |
| Wire-in: settings changes (all didSet) | ✅ Done |
| Flush on app shutdown | ✅ Done |

---

**Author:** Claude (Minh Thư) — 2026-03-09
