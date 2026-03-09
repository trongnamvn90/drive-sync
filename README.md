# 🔄 DriveSync

Một laptop, nhiều ổ cứng, để ở nhiều nơi.
Cắm bất kỳ ổ nào vào → data mới nhất. Rút ra → data an toàn trên cloud.

## Vấn đề

Ổ cứng ở nhà mà anh đang ở công ty. Ổ ở công ty mà anh đang ở quán cafe.
Luôn có ổ cứng **không ở bên mình**. Copy thủ công thì quên, chậm, sai version.

## Giải pháp

```
  Ổ nhà       Ổ công ty     Ổ mang theo      ...
    │             │              │
    └─────────────┴──────┬───────┘
                         │
                  cắm bất kỳ ổ nào
                         │
                  ┌──────▼──────┐
                  │  DriveSync  │
                  └──────┬──────┘
                         │
                  Google Drive (hub)
```

- N ổ cứng cùng tên, ở N nơi khác nhau
- Google Drive là hub trung tâm, luôn có bản mới nhất
- Cắm ổ → auto sync 2 chiều. Làm việc → file đổi, 30s sau upload
- Không có ổ? → drive.google.com vẫn truy cập được

## Kết quả

| Trước | Sau |
|-------|-----|
| Ổ ở chỗ khác → không có file | Cắm ổ nào cũng có |
| Quên copy trước khi đi | Không cần nhớ |
| Ổ hỏng = mất data | Cloud + các ổ khác còn |
| Copy thủ công, chậm | Chỉ sync file thay đổi |

## Scope v1

Một volume name, N ổ cứng, 1 Google Drive folder.
Auto sync khi cắm ổ, real-time khi làm việc, menubar hiện trạng thái.

## Setup (Developer)

### Google OAuth Credentials

App cần Google Cloud OAuth Client ID để kết nối Google Drive. Credentials không có trong repo — bạn phải tự tạo:

1. Vào [Google Cloud Console](https://console.cloud.google.com/)
2. Tạo project mới (hoặc dùng project có sẵn)
3. Bật **Google Drive API** và **Google People API**
4. Tạo OAuth Client ID: Application type = **Desktop app**
5. Copy `client_id` và `client_secret`
6. Tạo file `Sources/DriveSync/Secrets.swift`:

```swift
enum Secrets {
    static let googleClientId = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    static let googleClientSecret = "YOUR_CLIENT_SECRET"
}
```

File này nằm trong `.gitignore` — không bao giờ commit lên repo.

---

**Author:** Claude (Minh Thư) — 2026-03-05
**Chi tiết triển khai:** [TECHNICAL.md](./TECHNICAL.md)
