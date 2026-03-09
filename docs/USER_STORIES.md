# DriveSync — Use Cases & User Stories

## Actors

- **User**: Người dùng laptop, sở hữu nhiều ổ cứng để ở nhiều nơi
- **System**: DriveSync daemon + menubar app
- **Google Drive**: Cloud storage hub

---

## Use Cases

### UC-01: First-time Setup
User cài DriveSync, kết nối Google Drive, chuẩn bị ổ cứng.

### UC-02: Plug & Sync
User cắm ổ cứng vào laptop, system tự động đồng bộ.

### UC-03: Work & Sync
User làm việc trên ổ cứng, system tự sync file thay đổi lên cloud.

### UC-04: Safe Eject
User muốn rút ổ, system đảm bảo mọi thứ đã sync xong.

### UC-05: Monitor Status
User xem trạng thái sync trên menubar.

### UC-06: Force Sync
User chủ động yêu cầu sync ngay.

### UC-07: Pause/Resume
User tạm dừng sync (đang họp, mạng yếu...) rồi bật lại.

### UC-08: Access Without Drive
User cần file nhưng không có ổ bên mình.

### UC-09: Handle Conflict
Cùng 1 file bị sửa ở 2 nơi khác nhau giữa 2 lần sync.

### UC-10: Handle Offline
User làm việc khi không có mạng.

### UC-11: Diagnose Issues
Có lỗi xảy ra, user cần biết vấn đề ở đâu.

---

## User Stories

### Drive Registry

**US-16** — Onboard ổ mới
> Là user, tôi muốn đăng ký ổ cứng mới với DriveSync,
> để phần mềm biết đây là ổ của tôi và tự động sync khi cắm.

Acceptance criteria:
- `drivesync register` detect ổ đang cắm mà chưa có trong registry
- Hỏi user đặt tên (label) cho ổ, ví dụ "Ổ nhà", "Ổ công ty"
- Identify ổ bằng volume UUID (lấy qua DiskArbitration), không phải volume name
- Nếu ổ trống → confirm rồi pull từ cloud xuống
- Nếu ổ có data → full bisync (merge 2 chiều)
- Lưu vào registry (`~/.config/drivesync/config.toml`)
- Không giới hạn số lượng ổ

**US-17** — Unregister ổ
> Là user, tôi muốn xóa ổ khỏi DriveSync khi ổ hỏng hoặc bán đi,
> để registry không còn ổ "ma".

Acceptance criteria:
- `drivesync unregister` list các ổ đã đăng ký, chọn ổ cần xóa
- Xóa khỏi registry
- Option `--wipe` để xóa sạch data trên ổ trước khi unregister
- Không xóa data trên cloud (cloud là shared hub)

**US-18** — Cắm ổ chưa register
> Là user, tôi muốn được cảnh báo khi cắm ổ chưa đăng ký,
> để không bị sync nhầm vào ổ lạ.

Acceptance criteria:
- Cắm ổ có volume name khớp nhưng UUID không có trong registry → KHÔNG sync
- Notification: "Ổ [name] chưa đăng ký. Mở DriveSync để thêm."
- An toàn: không bao giờ sync vào ổ không biết

**US-19** — Ổ trùng UUID
> Là user, tôi muốn biết khi UUID bị trùng (clone ổ, restore partition),
> để tránh conflict giữa 2 ổ.

Acceptance criteria:
- Detect 2 ổ khác nhau cùng UUID → cảnh báo
- Yêu cầu format lại 1 trong 2 ổ để tạo UUID mới
- Không cho phép 2 ổ cùng UUID trong registry

---

### Setup

**US-01** — Cài đặt lần đầu
> Là user, tôi muốn setup DriveSync bằng 1 lệnh duy nhất,
> để tôi không cần tự cài từng tool rồi config thủ công.

Acceptance criteria:
- `drivesync setup` cài rclone, fswatch nếu chưa có
- Mở browser để OAuth login Google Drive
- Hỏi tên volume (mặc định: ZORRO)
- Tạo symlink ~/Drive
- Đăng ký launchd agent
- Chạy test sync 1 file để xác nhận hoạt động

**US-02** — Format ổ cứng
> Là user, tôi muốn biết cách format ổ cứng đúng tên,
> để DriveSync nhận diện được ổ khi cắm vào.

Acceptance criteria:
- `drivesync setup` hướng dẫn format ổ cùng tên
- Gợi ý file system phù hợp (exFAT cho cross-platform, APFS cho macOS-only)

---

### Daily Use

**US-03** — Cắm ổ, tự sync
> Là user, tôi muốn cắm ổ cứng vào và data tự đồng bộ,
> để tôi không cần nhớ chạy lệnh gì.

Acceptance criteria:
- Cắm ổ → sync bắt đầu trong 5s
- Bisync 2 chiều: file mới trên ổ → upload, file mới trên cloud → download
- Chỉ sync file thay đổi (incremental)
- Menubar icon chuyển từ 💤 → 🔄 → ✅

**US-04** — Làm việc, tự sync nền
> Là user, tôi muốn save file rồi nó tự upload lên cloud,
> để tôi không cần dừng việc để sync thủ công.

Acceptance criteria:
- File thay đổi → tối đa 30s sau bắt đầu upload
- Không ảnh hưởng performance khi đang làm việc
- Save liên tục (Ctrl+S nhiều lần) → gom lại, không spam upload
- File lớn upload nền, không block

**US-05** — Rút ổ an toàn
> Là user, tôi muốn rút ổ mà biết chắc data đã sync xong,
> để tôi không lo mất file chưa kịp upload.

Acceptance criteria:
- `drivesync eject` hoặc nút Eject trên menubar
- Chờ sync xong (nếu đang pending) → eject ổ
- Thông báo "Safe to remove" khi xong
- Nếu còn file chưa sync được (mất mạng) → cảnh báo trước khi eject
- Xóa symlink ~/Drive khi unmount

**US-06** — Cắm ổ khác, ở nơi khác
> Là user, tôi muốn cắm ổ ở công ty vào laptop và có file mới nhất mà tôi đã sửa ở nhà tối qua,
> để tôi tiếp tục làm việc liền mà không cần mang ổ theo.

Acceptance criteria:
- Ổ ở công ty pull bản mới nhất từ Google Drive
- File tôi sửa tối qua trên ổ nhà → đã trên cloud → download về ổ công ty
- Không cần thao tác gì ngoài cắm ổ

---

### Monitoring

**US-07** — Xem trạng thái trên menubar
> Là user, tôi muốn liếc mắt lên menubar là biết sync đang thế nào,
> để tôi yên tâm làm việc.

Acceptance criteria:
- Icon thay đổi theo state (💤 🔄 ✅ ⚠️)
- Click vào → dropdown: trạng thái, thời gian sync gần nhất, số file pending
- Không cần mở terminal

**US-08** — Xem log
> Là user, tôi muốn xem lịch sử sync gần đây,
> để tôi biết file nào đã sync, file nào lỗi.

Acceptance criteria:
- `drivesync log` hiện log gần nhất
- Menubar dropdown có mục "View Logs"
- Log ghi rõ: thời gian, file, action (upload/download), kết quả

---

### Control

**US-09** — Force sync
> Là user, tôi muốn bấm 1 nút để sync ngay lập tức,
> để tôi không cần chờ debounce hay periodic timer.

Acceptance criteria:
- `drivesync sync` hoặc nút "Sync Now" trên menubar
- Full bisync chạy ngay
- Feedback khi xong

**US-10** — Tạm dừng sync
> Là user, tôi muốn pause sync khi đang họp online hoặc mạng yếu,
> để sync không chiếm bandwidth.

Acceptance criteria:
- `drivesync pause` hoặc nút Pause trên menubar
- Sync dừng ngay, không upload/download
- Icon chuyển thành ⏸
- `drivesync resume` để bật lại
- File thay đổi trong lúc pause → queue lại, sync khi resume

---

### Edge Cases

**US-11** — Conflict resolution
> Là user, tôi muốn không bị mất file khi cùng 1 file bị sửa ở 2 ổ khác nhau,
> để tôi tự chọn version nào giữ.

Acceptance criteria:
- Không bao giờ ghi đè mất data
- Giữ cả 2 bản: `report.docx` + `report.docx.conflict-20260305`
- Notification cảnh báo có conflict
- User tự quyết định giữ bản nào

**US-12** — Làm việc offline
> Là user, tôi muốn vẫn làm việc bình thường khi không có mạng,
> để sync tự chạy khi có mạng lại.

Acceptance criteria:
- Không có mạng → file thay đổi được queue
- Có mạng lại → tự sync queue
- Menubar icon ⚠️ khi offline, ghi chú "X files pending"
- Không mất file, không lỗi

**US-13** — Diagnose
> Là user, tôi muốn biết vấn đề ở đâu khi sync không hoạt động,
> để tôi tự fix hoặc biết cách mô tả lỗi.

Acceptance criteria:
- `drivesync doctor` check: rclone OK? Google auth OK? ổ mounted? mạng OK? disk space OK?
- Output rõ ràng: ✅ / ❌ cho từng mục
- Gợi ý cách fix nếu có lỗi

---

### Access

**US-14** — Truy cập file không cần ổ
> Là user, tôi muốn lấy file khi không có ổ cứng bên mình,
> để tôi không bị block công việc.

Acceptance criteria:
- Mở drive.google.com → folder DriveSync → có tất cả file
- Đây là tính năng "miễn phí" by design, không cần code gì

**US-15** — Truy cập nhanh qua symlink
> Là user, tôi muốn gõ `cd ~/Drive` thay vì `cd /Volumes/ZORRO`,
> để truy cập ổ nhanh hơn.

Acceptance criteria:
- Symlink ~/Drive → /Volumes/ZORRO khi ổ mount
- Rút ổ → symlink trỏ tới path không tồn tại (báo lỗi rõ ràng, không nhầm)

---

## Dependency Order

```
US-01 Setup
  └→ US-16 Register ổ
      ├→ US-18 Cắm ổ chưa register (guard)
      ├→ US-19 Trùng UUID (guard)
      └→ US-03 Plug & sync
          ├→ US-15 Symlink
          ├→ US-06 Ổ khác, nơi khác (free by design)
          ├→ US-04 Work & sync (FSEvents + debounce)
          │   └→ US-09 Force sync
          ├→ US-05 Safe eject
          ├→ US-08 View log
          └→ US-07 Menubar status
              └→ US-10 Pause/Resume

US-02 Format guide (standalone, docs only)
US-13 Diagnose (standalone, bất kỳ lúc nào)
US-14 Access no drive (free by design)
US-17 Unregister ổ (cần US-16)

US-11 Conflict ──┐
US-12 Offline  ──┤ cần US-03 + US-04 hoạt động trước
                 └→ hardening layer, làm sau cùng
```
