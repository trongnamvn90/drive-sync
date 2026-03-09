# PRD-002: Rclone Communication

## Mục tiêu

Định nghĩa cách DriveSync giao tiếp với rclone — gọi lệnh, truyền config, theo dõi progress, kiểm soát process. Đây là lớp trung gian giữa Core Library và rclone subprocess.

## Scope

| Trong scope | Ngoài scope |
|-------------|-------------|
| Gọi rclone subprocess từ Swift | Sync flow (khi nào gọi sync, trigger gì) |
| Truyền OAuth token sang rclone config | OAuth flow (PRD-001) |
| Parse output (progress, errors) | UI hiển thị progress |
| Process lifecycle (start, pause, resume, cancel) | FSEvents / MountDetector |
| Kiểm tra rclone có sẵn (`doctor`) | Tự cài rclone |

## Nguyên tắc

**rclone làm heavy lifting, app chỉ điều phối.**

- Gọi `rclone bisync` cho mọi sync operation — không tự implement so sánh file
- App kiểm soát process lifecycle (start/pause/resume/cancel)
- Parse stdout để lấy progress realtime
- Parse stderr để detect lỗi

## Kiến trúc

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  SyncEngine  │────→│ RcloneRunner │────→│   rclone     │
│  (Core)      │     │  (Core)      │     │  (subprocess)│
│              │←────│              │←────│              │
│  quyết định  │ progress/error │  quản lý   │  stdout/stderr
│  khi nào sync│     │  process     │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
```

- **SyncEngine**: quyết định khi nào sync (mount, file change, periodic, force)
- **RcloneRunner**: gọi rclone process, parse output, quản lý lifecycle
- **rclone**: subprocess thực thi, app không can thiệp logic sync

## Rclone Config

### Tạo remote từ OAuth token

Sau khi PRD-001 lấy được token, truyền sang rclone:

```bash
rclone config create gdrive drive \
  client_id="{CLIENT_ID}" \
  client_secret="{CLIENT_SECRET}" \
  token='{"access_token":"ya29.xxx","refresh_token":"1//xxx","expiry":"2026-03-06T15:30:00Z"}' \
  root_folder_id="" \
  scope="drive"
```

- Chạy 1 lần sau OAuth thành công
- rclone tự lưu vào `~/.config/rclone/rclone.conf`
- rclone tự refresh token khi cần (dùng client_id/secret đã truyền)
- Khi app re-login (PRD-001) → chạy lại `config create` để ghi đè token mới

### Config file location

Dùng default rclone config: `~/.config/rclone/rclone.conf`. Không custom path — tránh phức tạp.

## Các lệnh rclone sử dụng

### 1. Bisync (chính)

```bash
rclone bisync /Volumes/ZORRO gdrive:DriveSync \
  --progress \
  --stats 1s \
  --stats-one-line \
  --exclude ".DS_Store" \
  --exclude ".Spotlight-V100/**" \
  --exclude ".Trashes/**" \
  --exclude ".fseventsd/**" \
  --exclude "._*" \
  --exclude "*.tmp" \
  --exclude "~$*" \
  --bwlimit "{UPLOAD_LIMIT}:{DOWNLOAD_LIMIT}" \
  --conflict-resolve newer \
  --conflict-suffix .conflict-{DateOnly} \
  --resilient \
  --recover \
  --verbose
```

Dùng cho:
- Full sync khi cắm ổ
- Incremental sync sau file change (debounce 30s)
- Periodic sync mỗi 15 phút

Flags quan trọng:
| Flag | Mục đích |
|------|----------|
| `--progress --stats 1s --stats-one-line` | Parse progress realtime |
| `--exclude` | Bỏ qua system files (từ config) |
| `--bwlimit` | Bandwidth limit (từ Settings) |
| `--conflict-resolve newer` | Giữ bản mới hơn làm chính |
| `--conflict-suffix` | Bản cũ hơn rename thành `.conflict-YYYYMMDD` |
| `--resilient --recover` | Tự recover nếu bisync bị gián đoạn lần trước |
| `--verbose` | Log chi tiết cho debug |

### 2. About (storage quota)

```bash
rclone about gdrive: --json
```

Output:
```json
{
  "total": 16106127360,
  "used": 12884901888,
  "free": 3221225472
}
```

Dùng khi: mở tab Google Drive trong Settings, bổ sung cho PRD-001 (email lấy từ Google API, storage có thể lấy từ rclone).

### 3. Doctor (kiểm tra)

```bash
rclone version
```

Kiểm tra rclone có cài hay chưa + version. Dùng cho warning state trong menu dropdown.

### 4. Mkdir (tạo folder)

```bash
rclone mkdir gdrive:DriveSync
```

Tạo folder trên Google Drive nếu chưa có. Chạy 1 lần sau khi config remote.

## Process Lifecycle

### Start

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: rclonePath)
process.arguments = [...]
process.standardOutput = outputPipe
process.standardError = errorPipe
try process.run()
```

- `rclonePath`: tìm bằng `which rclone` hoặc kiểm tra các path phổ biến (`/usr/local/bin/rclone`, `/opt/homebrew/bin/rclone`)
- Pipe stdout + stderr để parse realtime

### Pause

```swift
process.suspend()  // gửi SIGSTOP
```

- rclone process dừng ngay, giữ nguyên state
- Không mất data — transfer đang dở sẽ resume được

### Resume

```swift
process.resume()  // gửi SIGCONT
```

- rclone tiếp tục từ chỗ dừng

### Cancel

```swift
process.terminate()  // gửi SIGTERM
```

- rclone cleanup: xóa temp files, không để file dở dang
- Nếu 5s chưa tắt → `process.interrupt()` (SIGINT)
- Nếu 10s vẫn chưa tắt → kill -9 (last resort)

### Exit code

| Code | Ý nghĩa | App xử lý |
|------|----------|------------|
| 0 | Thành công | → state WATCHING |
| 1 | Lỗi syntax/usage | → log error, không retry |
| 2 | Lỗi transfer (một số file fail) | → retry, báo warning |
| 3 | Lỗi directory not found | → kiểm tra ổ còn mount không |
| 9 | Bisync bị gián đoạn lần trước | → chạy lại với `--resync` |

## Parse Progress

rclone với `--progress --stats 1s --stats-one-line` output dạng:

```
Transferred:   120.5 MiB / 260.0 MiB, 46%, 15.2 MiB/s, ETA 9s
Transferred:        3 / 10, 30%
```

Parse bằng regex:
```
Transferred:\s+([\d.]+)\s+(\w+)\s+/\s+([\d.]+)\s+(\w+),\s+(\d+)%
Transferred:\s+(\d+)\s+/\s+(\d+),\s+(\d+)%
```

Trích xuất:
- `bytesTransferred` / `bytesTotal` → progress bar
- `filesTransferred` / `filesTotal` → "3/10 files"
- `percentage` → phần trăm
- `speed` → tốc độ hiện tại
- `eta` → thời gian còn lại

Update UI mỗi giây (theo stats interval).

## Parse Errors

Stderr patterns cần detect:

| Pattern | Ý nghĩa | App xử lý |
|---------|----------|------------|
| `no such host` / `dial tcp` | Mất mạng | → state WARNING, queue |
| `oauth2: token expired` | Token hết hạn | → gọi PRD-001 refresh |
| `directory not found` | Folder bị xóa | → tạo lại bằng `mkdir` |
| `bisync aborted` | Bisync lỗi nặng | → chạy `--resync` |
| `access denied` / `403` | Hết quyền | → state ERROR, yêu cầu re-login |
| `quota exceeded` | Hết dung lượng | → state ERROR, notification |

## Core Module

### RcloneRunner (trong Core Library)

```swift
protocol RcloneRunnerProtocol {
    func bisync(source: String, destination: String, options: SyncOptions) async throws -> SyncResult
    func about(remote: String) async throws -> StorageInfo
    func configCreate(name: String, params: [String: String]) async throws
    func mkdir(path: String) async throws
    func version() async throws -> String

    var progressStream: AsyncStream<SyncProgress> { get }

    func pause()
    func resume()
    func cancel()
}

struct SyncOptions {
    let excludes: [String]
    let bwLimit: String       // "UPLOAD:DOWNLOAD" KB/s, "0" = unlimited
    let resync: Bool          // true khi bisync bị gián đoạn lần trước
}

struct SyncProgress {
    let bytesTransferred: Int64
    let bytesTotal: Int64
    let filesTransferred: Int
    let filesTotal: Int
    let percentage: Int
    let speed: String         // "15.2 MiB/s"
    let eta: String           // "9s"
}

struct SyncResult {
    let success: Bool
    let filesUploaded: Int
    let filesDownloaded: Int
    let conflicts: [String]   // file paths bị conflict
    let errors: [String]      // error messages
}

struct StorageInfo {
    let total: Int64
    let used: Int64
    let free: Int64
}
```

Cần testable:
- `ProcessRunner` protocol để mock subprocess trong test
- Không gọi `Process()` trực tiếp — wrap lại để inject

## Mối quan hệ với PRD-001

```
PRD-001: OAuth → lấy token → lưu auth.json
                                    │
                                    ▼
PRD-002: đọc token ← auth.json → rclone config create → rclone.conf
                                                              │
                                                              ▼
                                                    rclone bisync (dùng token từ rclone.conf)
```

- App quản lý token (PRD-001), rclone dùng token qua config
- Khi token refresh (PRD-001) → cập nhật lại rclone config
- rclone cũng tự refresh token nếu cần (backup, nhưng app nên chủ động)

## Edge Cases

| Tình huống | Xử lý |
|------------|--------|
| rclone chưa cài | Warning trong menu, `drivesync doctor` báo lỗi |
| rclone version quá cũ (< 1.58, chưa có bisync) | Cảnh báo cần update |
| Ổ bị rút giữa sync | rclone exit code 3, app detect → state IDLE |
| Mất mạng giữa sync | rclone retry tự động, fail → app queue |
| 2 sync chạy đồng thời | Không cho phép — lock, queue sync tiếp theo |
| rclone process bị kill bởi OS | Detect process exit → retry với `--recover` |
| Bisync lần đầu (chưa có listing file) | Tự động chạy `--resync` |
| File rất lớn (>1GB) | rclone tự handle chunked upload, resume |

## Acceptance Criteria

- [ ] Gọi `rclone bisync` thành công từ Swift subprocess
- [ ] Parse progress realtime (bytes, files, percentage, speed)
- [ ] Pause/Resume rclone process bằng SIGSTOP/SIGCONT
- [ ] Cancel rclone process gracefully (SIGTERM → SIGINT → kill)
- [ ] Detect exit codes và xử lý phù hợp
- [ ] Detect errors từ stderr (mất mạng, token expired, quota exceeded)
- [ ] Truyền OAuth token từ auth.json sang rclone config
- [ ] `rclone about` lấy storage info
- [ ] `rclone version` kiểm tra rclone có sẵn
- [ ] Lock: không cho 2 sync chạy đồng thời
- [ ] Unit test: mock Process → test parse progress, errors, lifecycle

---

## ❌ Implementation Status

**Not started** — PRD written 2026-03-06, awaiting implementation.

No code exists yet for `RcloneRunner`, `SyncEngine`, or any rclone subprocess integration.

---

**Author:** Claude (Minh Thư) — 2026-03-06
