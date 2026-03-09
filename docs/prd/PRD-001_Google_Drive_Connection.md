# PRD-001: Google Drive Connection

## Mục tiêu

User kết nối Google Drive từ app, không cần rclone. App tự handle OAuth 2.0, lưu token, hiện thông tin account. Đây là bước đầu tiên trước khi sync bất cứ thứ gì.

## Scope

| Trong scope | Ngoài scope |
|-------------|-------------|
| OAuth 2.0 Authorization Code flow | Sync file |
| Lưu + refresh token | rclone config |
| Hiện email, storage quota | Bandwidth limit (chỉ UI, chưa cần hoạt động) |
| Connect / Disconnect / Re-login | Service Account flow |
| Tab Google Drive trong Settings | Các tab khác |
| Warning "Google Drive not connected" trong menu | Setup wizard |

## Kiến trúc

```
User bấm "Connect Google Drive"
    │
    ▼
App mở browser → Google OAuth consent screen
    │
    ▼
User đồng ý → Google redirect về http://127.0.0.1:{port}/callback
    │
    ▼
App (local HTTP server) bắt authorization code
    │
    ▼
App POST code → https://oauth2.googleapis.com/token → nhận token JSON
    │
    ▼
App lưu token vào ~/.config/drivesync/auth.json
    │
    ▼
App gọi Google API lấy email + storage → hiện lên UI
```

## Chi tiết kỹ thuật

### 1. Google Cloud Project

App cần 1 Google Cloud OAuth Client ID (Desktop app type):
- `client_id` và `client_secret` lưu trong file `Sources/DriveSync/Secrets.swift` (hardcode)
- File này nằm trong `.gitignore` — không commit lên repo
- Developer tự tạo Google Cloud project và điền credentials (xem README)
- Scopes yêu cầu:
  - `https://www.googleapis.com/auth/drive` — full Drive access (cần cho bisync sau này)
  - `https://www.googleapis.com/auth/userinfo.email` — lấy email hiển thị

### 2. OAuth Flow

**Bước 1: Mở browser**
```
https://accounts.google.com/o/oauth2/v2/auth?
  client_id={CLIENT_ID}
  &redirect_uri=http://127.0.0.1:{PORT}/callback
  &response_type=code
  &scope=https://www.googleapis.com/auth/drive+https://www.googleapis.com/auth/userinfo.email
  &access_type=offline
  &prompt=consent
```

- `PORT`: random available port (tránh conflict), range 49152–65535
- `prompt=consent`: luôn hỏi lại để lấy refresh_token
- `access_type=offline`: bắt buộc để có refresh_token

**Bước 2: Local HTTP server**
- Chạy trên `127.0.0.1:{PORT}`, chỉ listen 1 request
- Timeout: 120 giây, quá thì tắt server + báo lỗi
- Nhận `GET /callback?code=xxx` → extract code
- Trả về HTML đơn giản: "Connected! You can close this tab."
- Tắt server ngay sau khi nhận code

**Bước 3: Exchange code → token**
```
POST https://oauth2.googleapis.com/token
Content-Type: application/x-www-form-urlencoded

code={CODE}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&redirect_uri=http://127.0.0.1:{PORT}/callback
&grant_type=authorization_code
```

Response:
```json
{
  "access_token": "ya29.xxx",
  "refresh_token": "1//xxx",
  "expires_in": 3600,
  "token_type": "Bearer",
  "scope": "..."
}
```

**Bước 4: Lưu token**

File: `~/.config/drivesync/auth.json`
```json
{
  "access_token": "ya29.xxx",
  "refresh_token": "1//xxx",
  "expires_at": "2026-03-06T15:30:00Z",
  "email": "zorro@gmail.com"
}
```

- `expires_at` = now + `expires_in` seconds
- File permissions: `0600` (chỉ owner đọc/ghi)
- Không lưu trong config.toml (tách auth ra riêng)

### 3. Token Refresh

Khi `access_token` hết hạn (check `expires_at` trước mỗi API call):

```
POST https://oauth2.googleapis.com/token

refresh_token={REFRESH_TOKEN}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&grant_type=refresh_token
```

- Refresh thành công → cập nhật `access_token` + `expires_at` trong auth.json
- Refresh thất bại (token bị revoke, 400/401) → chuyển về trạng thái disconnected, yêu cầu re-login
- Refresh proactively: khi token còn < 5 phút trước expiry

### 4. Lấy thông tin account

**Email:**
```
GET https://www.googleapis.com/oauth2/v2/userinfo
Authorization: Bearer {ACCESS_TOKEN}
```
→ `response.email`

**Storage quota:**
```
GET https://www.googleapis.com/drive/v3/about?fields=storageQuota
Authorization: Bearer {ACCESS_TOKEN}
```
→ `response.storageQuota.limit`, `response.storageQuota.usage`

**Folder list (root-level):**
```
GET https://www.googleapis.com/drive/v3/files?q=mimeType='application/vnd.google-apps.folder'+and+'root'+in+parents+and+trashed=false&fields=files(id,name)&orderBy=name&pageSize=100
Authorization: Bearer {ACCESS_TOKEN}
```
→ `response.files[].name` — hiển thị trong Picker dropdown để user chọn sync folder

Gọi cả ba khi:
- Vừa connect thành công
- Mỗi lần mở tab Google Drive trong Settings
- Không cần poll liên tục

### 5. Disconnect

- Revoke token trên Google:
  ```
  POST https://oauth2.googleapis.com/revoke?token={ACCESS_TOKEN}
  ```
- Xóa `~/.config/drivesync/auth.json`
- UI chuyển về trạng thái "Not connected"
- Revoke fail (mất mạng) → vẫn xóa local token, coi như disconnected

### 6. Re-login

- Chạy lại OAuth flow từ đầu (bước 1)
- Ghi đè auth.json cũ
- Use case: đổi account, token bị lỗi, cần cấp lại quyền

## UI Spec

### Tab Google Drive — 3 states

Tab nằm trong Settings window (tab đầu tiên). Dùng macOS native Form grouped style.

#### State 1: Disconnected

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  Status: (xmark.circle.fill) Not connected│
│                                           │
│  ┌─────────────────────────────────────┐  │
│  │                                     │  │
│  │      (icloud.slash)  ← SF Symbol    │  │
│  │                                     │  │
│  │  Connect your Google Drive to start │  │
│  │  syncing files between your         │  │
│  │  external drives and the cloud.     │  │
│  │                                     │  │
│  │  [(link) Connect Google Drive]      │  │
│  │       ↑ borderedProminent, large    │  │
│  │                                     │  │
│  └─────────────────────────────────────┘  │
│                                           │
└───────────────────────────────────────────┘
```

- Icon `icloud.slash` size 36pt, secondary color
- Mô tả text: callout size, secondary color, center-aligned
- Nút Connect: `borderedProminent`, `controlSize(.large)`, icon `link`

#### State 2: Connecting (đang chờ OAuth)

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  Status: (spinner) Waiting for Google...  │
│                                           │
│  A browser window should have opened.     │
│  Sign in with your Google account         │
│  to continue.                             │
│                                           │
│  [Cancel]                                 │
│                                           │
└───────────────────────────────────────────┘
```

- ProgressView spinner nhỏ (controlSize small) bên cạnh text "Waiting for Google..."
- Text hướng dẫn: callout, secondary
- Nút Cancel: plain style
- Timeout 120s → tự chuyển về Disconnected + hiện lỗi inline

#### State 3: Connected

```
┌───────────────────────────────────────────┐
│ [Google Drive] [Drives] [Sync] [App]      │
│───────────────────────────────────────────│
│                                           │
│  ┌─ Section ──────────────────────────┐   │
│  │ Status:  (checkmark.circle.fill)   │   │
│  │          Connected    ← green      │   │
│  │ Account: zorro@gmail.com           │   │
│  │ Storage: 12 GB / 15 GB            │   │
│  │          [████████████░░░] 80%     │   │
│  │          ↑ tint red khi >90%       │   │
│  │ Folder:  [ DriveSync     ▾ ]       │   │
│  │          ↑ Picker dropdown        │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section ──────────────────────────┐   │
│  │ (arrow.counterclockwise) Re-login  │   │
│  │                    (xmark.circle)  │   │
│  │                    Disconnect ← red│   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section: Bandwidth ──────────────┐   │
│  │ Upload:   [  0  ] KB/s            │   │
│  │           (0 = unlimited) ← caption│   │
│  │ Download: [  0  ] KB/s            │   │
│  │           (0 = unlimited) ← caption│   │
│  └────────────────────────────────────┘   │
│                                           │
└───────────────────────────────────────────┘
```

Layout chi tiết:
- Dùng `LabeledContent` cho mỗi row (Status, Account, Storage, Folder)
- Storage bar: `ProgressView(value:)`, width 140pt, tint `.blue` bình thường, `.red` khi >90%
- Folder: `Picker` dropdown, width 180pt, danh sách folder lấy từ root Google Drive
- Re-login và Disconnect: nằm cùng 1 `HStack`, Re-login bên trái, Disconnect bên phải
- Disconnect: `role: .destructive` → text đỏ
- Bấm Disconnect → hiện **confirm alert**:
  - Title: "Disconnect Google Drive?"
  - Message: "Token will be revoked. You'll need to re-connect to sync."
  - Buttons: [Cancel] [Disconnect (destructive)]
- Bandwidth fields: `TextField` number format, width 60pt, `textFieldStyle(.roundedBorder)`
- Thay đổi bandwidth → lưu ngay vào `config.toml` (`[bandwidth]` section), RcloneRunner đọc khi sync

### Menu Dropdown — Warning states

Khi Google Drive chưa connected, menu dropdown thay đổi header:

```
┌──────────────────────────────────────┐
│  (exclamationmark.triangle.fill)     │
│  Setup Required           ← headline │
│──────────────────────────────────────│
│  (xmark.circle) Google Drive         │
│  not connected            ← button   │
│──────────────────────────────────────│
│  ...các menu item khác...            │
└──────────────────────────────────────┘
```

- Header dùng `Label` với SF Symbol `exclamationmark.triangle.fill`
- "Google Drive not connected" là `Button` — click → mở Settings window (tab Google Drive)
- Khi đang connecting: text đổi thành "Google Drive connecting...", icon `arrow.triangle.2.circlepath`
- Khi connected: header trở về trạng thái bình thường (hiện sync state)
- Các menu item như Sync Now, Pause, Open Folder → `disabled` khi chưa connected

### Transitions

```
Disconnected ──(bấm Connect)──→ Connecting
Connecting ──(OAuth thành công)──→ Connected
Connecting ──(Cancel / Timeout 120s / Error)──→ Disconnected
Connected ──(bấm Disconnect + confirm)──→ Disconnected
Connected ──(bấm Re-login)──→ Connecting
Connected ──(token refresh fail)──→ Disconnected (+ inline error message)
```

### Error States (inline, không dùng alert)

Hiện bên dưới Status row khi có lỗi:

```
│  Status: (xmark.circle.fill) Not connected │
│  (exclamationmark.triangle) Connection      │
│  timed out. Please try again.   ← red text  │
```

Các error messages:
| Lỗi | Message |
|-----|---------|
| Timeout 120s | "Connection timed out. Please try again." |
| Không có mạng | "No internet connection." |
| OAuth bị từ chối | "Access denied. Please try again." |
| Token refresh fail | "Session expired. Please re-connect." |

Error message tự biến mất khi user bấm Connect lại.

### Typography & Spacing

- Dùng macOS `.formStyle(.grouped)` — hệ thống tự handle spacing giữa sections
- Labels: system default font
- Secondary info: `.foregroundStyle(.secondary)`
- Caption text (bandwidth hint): `.font(.caption)`, `.foregroundStyle(.tertiary)`
- Tất cả icon dùng SF Symbols — không dùng emoji

## Core Module

### GoogleAuth (trong Core Library)

```swift
// Public interface
protocol GoogleAuthProtocol {
    var isConnected: Bool { get }
    var account: GoogleAccount? { get }

    func connect() async throws -> GoogleAccount
    func disconnect() async throws
    func refreshIfNeeded() async throws -> String  // returns valid access_token
}

struct GoogleAccount {
    let email: String
    let storageUsed: Int64   // bytes
    let storageTotal: Int64  // bytes
}
```

Cần testable:
- `HTTPClient` protocol để mock network calls trong test
- `TokenStore` protocol để mock file I/O
- Không dùng singleton — inject dependencies

## Edge Cases

| Tình huống | Xử lý |
|------------|--------|
| User đóng browser không đồng ý | Timeout 120s → báo "Connection cancelled" |
| User đồng ý nhưng app crash trước khi lưu token | Lần sau mở app → vẫn disconnected, user connect lại |
| Port bị chiếm | Retry với port khác (tối đa 3 lần) |
| Không có mạng khi connect | Báo lỗi ngay, không mở browser |
| Token bị revoke từ Google Security settings | Refresh fail → chuyển disconnected, thông báo re-login |
| auth.json bị xóa/corrupt | Coi như disconnected |
| Nhiều instance app chạy cùng lúc | File lock trên auth.json khi write |

## Acceptance Criteria

- [ ] Bấm "Connect Google Drive" → mở browser → OAuth → về app → hiện email + storage
- [ ] Token tự refresh khi hết hạn, user không cần làm gì
- [ ] Bấm "Disconnect" → revoke + xóa token → UI chuyển về "Not connected"
- [ ] Bấm "Re-login" → chạy lại OAuth → cập nhật account mới
- [ ] Tắt app mở lại → vẫn connected (đọc auth.json)
- [ ] auth.json permission 0600
- [ ] Timeout 120s nếu user không hoàn tất OAuth
- [ ] Menu dropdown hiện warning khi chưa connected
- [ ] Unit test: mock HTTP → test connect, refresh, disconnect flows

## Không làm

- Credentials (`client_id`, `client_secret`) hardcode trong `Secrets.swift`, file nằm trong `.gitignore`
- Không support nhiều Google account cùng lúc (v2+)
- Không sync file — PRD khác
- Bandwidth: UI lưu giá trị vào `config.toml` (`upload_limit`, `download_limit`), RcloneRunner đọc khi sync (PRD-002)

---

**Author:** Claude (Minh Thư) — 2026-03-06
