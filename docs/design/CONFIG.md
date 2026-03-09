# DriveSync — Config Design

4 nhóm config độc lập, thay đổi riêng không ảnh hưởng nhau.

## 1. Google Drive

| Key | Default | Mô tả |
|-----|---------|-------|
| `remote` | `"gdrive"` | Tên rclone remote |
| `folder` | `"DriveSync"` | Folder trên Google Drive |
| `upload_limit` | `"0"` (unlimited) | Giới hạn upload bandwidth |
| `download_limit` | `"0"` (unlimited) | Giới hạn download bandwidth |

- Tự detect chưa có token → mở browser login
- Token expired → tự refresh, fail thì yêu cầu login lại
- Folder "DriveSync/" tạo tự động nếu chưa có

## 2. Drives (Registry)

```toml
[[drives]]
id = "drive-home"
label = "Ổ nhà"
volume_uuid = "A1B2C3D4-..."
registered_at = 2026-03-05
```

- Identify bằng volume UUID (DiskArbitration)
- Không giới hạn số lượng ổ
- Cắm ổ lạ → không sync, gợi ý register
- Trùng UUID → bắt format lại
- Unregister có option wipe data trên ổ, không xóa cloud

## 3. Sync

| Key | Default | Mô tả |
|-----|---------|-------|
| `debounce_seconds` | `30` | Chờ sau file change trước khi sync |
| `periodic_minutes` | `15` | Bisync định kỳ (catch cloud-side changes) |
| `exclude` | `.DS_Store`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `._*`, `*.tmp`, `~$*` | Patterns bỏ qua |

## 4. App

| Key | Default | Mô tả |
|-----|---------|-------|
| `launch_at_login` | `true` | Tự mở khi đăng nhập |
| `notifications` | `true` | Bật/tắt notification |
| `symlink` | `"~/Drive"` | Symlink trỏ tới ổ đang cắm |
| `log_level` | `"info"` | `debug`, `info`, `warn`, `error` |
| `log_retention_days` | `30` | Giữ log bao nhiêu ngày |

## Config file

Lưu tại `~/.config/drivesync/config.toml`. Defaults thông minh — user chỉ cần đổi khi muốn.

---

**Author:** Claude (Minh Thư) — 2026-03-05
