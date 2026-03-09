# TEST-001: Google Drive Connection

Test scenarios cho [PRD-001](./PRD-001_Google_Drive_Connection.md).

---

## TC-01: Connect lần đầu (happy path)

**Precondition:** App vừa cài, chưa có `auth.json`

| Step | Action | Expected |
|------|--------|----------|
| 1 | Mở app | Menubar icon hiện, menu dropdown hiện "Setup Required" + "Google Drive not connected" |
| 2 | Click "Google Drive not connected" trong menu | Settings window mở, tab Google Drive, state "Not connected" |
| 3 | Click "Connect Google Drive" | UI chuyển sang "Waiting for Google..." + spinner. Browser mở trang Google OAuth consent |
| 4 | Đăng nhập Google + đồng ý | Browser hiện "Connected! You can close this tab." |
| 5 | Quay lại app | Tab Google Drive hiện: Status Connected, email, storage bar, folder "DriveSync" |
| 6 | Check menu dropdown | Không còn "Setup Required" (trừ khi thiếu điều kiện khác) |
| 7 | Check file `~/.config/drivesync/auth.json` | File tồn tại, permission 0600, chứa access_token + refresh_token + email |

---

## TC-02: Connect — user từ chối OAuth

**Precondition:** App chưa connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click "Connect Google Drive" | Browser mở OAuth consent |
| 2 | Click "Cancel" / "Deny" trên Google | Browser hiện lỗi |
| 3 | Quay lại app | Tab chuyển về "Not connected" + error inline "Access denied. Please try again." |

---

## TC-03: Connect — user đóng browser không làm gì

**Precondition:** App chưa connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click "Connect Google Drive" | UI hiện "Waiting for Google...", browser mở |
| 2 | Đóng browser, không làm gì | |
| 3 | Đợi 120 giây | UI chuyển về "Not connected" + error inline "Connection timed out. Please try again." |

---

## TC-04: Connect — user bấm Cancel trong app

**Precondition:** App đang ở state "Waiting for Google..."

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click "Cancel" trong tab Google Drive | UI chuyển về "Not connected" ngay lập tức |
| 2 | Check | Không có error message (user chủ động cancel) |

---

## TC-05: Connect — không có mạng

**Precondition:** Tắt Wi-Fi / rút cáp mạng

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click "Connect Google Drive" | Error inline "No internet connection." KHÔNG mở browser |

---

## TC-06: Disconnect (happy path)

**Precondition:** App đang connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Mở Settings → tab Google Drive | Hiện email, storage, bandwidth |
| 2 | Click "Disconnect" | Confirm alert hiện: "Disconnect Google Drive?" |
| 3 | Click "Cancel" trên alert | Không có gì thay đổi, vẫn connected |
| 4 | Click "Disconnect" lần nữa → click "Disconnect" trên alert | UI chuyển về "Not connected" |
| 5 | Check `auth.json` | File đã bị xóa |
| 6 | Check menu dropdown | Hiện "Setup Required" + "Google Drive not connected" |

---

## TC-07: Re-login (đổi account)

**Precondition:** App đang connected với account A

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click "Re-login" | UI chuyển sang "Waiting for Google...", browser mở OAuth |
| 2 | Đăng nhập bằng account B | Browser hiện "Connected! You can close this tab." |
| 3 | Quay lại app | Email hiện account B, storage cập nhật theo account B |
| 4 | Check `auth.json` | Token mới của account B |

---

## TC-08: Persist sau khi tắt/mở app

**Precondition:** App đang connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Quit DriveSync | App tắt |
| 2 | Mở lại DriveSync | App khởi động, tab Google Drive hiện Connected với email + storage đúng |
| 3 | Check menu dropdown | Không hiện warning "Google Drive not connected" |

---

## TC-09: auth.json bị xóa/corrupt

**Precondition:** App đang connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Xóa file `~/.config/drivesync/auth.json` bằng terminal | |
| 2 | Mở Settings → tab Google Drive (hoặc đợi app detect) | UI chuyển về "Not connected" |
| 3 | Menu dropdown | Hiện warning "Google Drive not connected" |

---

## TC-10: Token expired — tự refresh

**Precondition:** App connected, access_token sắp hết hạn (< 5 phút)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Mở tab Google Drive | App tự gọi refresh token ở background |
| 2 | Check | Email + storage load bình thường, không hiện lỗi. User không cần làm gì |
| 3 | Check `auth.json` | `access_token` và `expires_at` đã cập nhật |

---

## TC-11: Token bị revoke từ Google

**Precondition:** App connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Vào https://myaccount.google.com/permissions → revoke DriveSync | |
| 2 | Mở tab Google Drive (hoặc đợi refresh cycle) | UI chuyển về "Not connected" + error inline "Session expired. Please re-connect." |

---

## TC-12: Storage bar — hiển thị đúng

**Precondition:** App connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Mở tab Google Drive | Storage hiện đúng format: "X GB / Y GB" |
| 2 | Check progress bar | Tỉ lệ bar khớp với số liệu |
| 3 | Nếu storage > 90% | Progress bar chuyển màu đỏ |

---

## TC-13: Bandwidth — lưu config

**Precondition:** App connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Đổi Upload thành 500, Download thành 1000 | |
| 2 | Check `~/.config/drivesync/config.toml` | `upload_limit = 500`, `download_limit = 1000` |
| 3 | Đổi lại về 0 | Config cập nhật `upload_limit = 0`, `download_limit = 0` |

---

## TC-14: Folder name — thay đổi

**Precondition:** App connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Đổi Folder từ "DriveSync" thành "MyBackup" | |
| 2 | Check `config.toml` | `folder = "MyBackup"` |

---

## TC-15: Menu dropdown — warning dynamic

**Precondition:** App chưa connected

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click menubar icon | Header: "Setup Required", item: "Google Drive not connected" |
| 2 | Check Sync Now, Pause, Open Folder | Các button bị disabled (greyed out) |
| 3 | Connect Google Drive thành công | |
| 4 | Click menubar icon lại | Header trở về trạng thái bình thường (idle/syncing/etc.), các button enabled |

---

**Author:** Claude (Minh Thư) — 2026-03-06
