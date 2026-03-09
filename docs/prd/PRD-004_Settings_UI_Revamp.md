# PRD-004: Settings UI Revamp

## Mục tiêu

Chuyển Settings window từ UI "code xong chạy được" sang UI chuẩn macOS native, tuân thủ Apple HIG. User mở Settings phải cảm thấy quen thuộc như bất kỳ macOS app nào khác.

## Vấn đề hiện tại

| Vấn đề | Mô tả |
|---------|--------|
| Dùng `Window` thủ công | Không có phím tắt ⌘, không có menu "Settings...", phải tự quản lý lifecycle |
| Toggle dùng switch style | macOS native dùng checkbox, switch là pattern của iOS |
| TextField cho số có range | Debounce (5–300), periodic (5–60), keep logs (1–365) — TextField không hint được range, dễ nhập sai |
| Bandwidth dùng TextField | 0 = unlimited không rõ nghĩa, không có step control |
| Window sizing thủ công | `minHeight: 560` hardcode, không adapt theo content |

## Scope

| Trong scope | Ngoài scope |
|-------------|-------------|
| Chuyển sang `Settings` scene | Thêm settings mới |
| Đổi control types cho đúng HIG | Logic thay đổi |
| Fix sizing/layout | Thay đổi config.toml format |
| Checkbox style cho toggles | Thêm @AppStorage (giữ ConfigManager) |

## Thay đổi chi tiết

### 1. `Settings` scene thay `Window`

**Trước:**
```swift
Window("Settings", id: "settings") {
    SettingsView(appState: appDelegate.appState)
}
.defaultSize(width: 580, height: 450)
```

**Sau:**
```swift
Settings {
    SettingsView(appState: appDelegate.appState)
}
```

**Lợi ích:**
- Tự thêm menu item "Settings..." trong app menu
- Tự bind phím tắt ⌘,
- Chỉ cho phép 1 instance window
- Tự quản lý window lifecycle (đóng/mở)
- macOS tự đặt title "Settings" (hoặc "Preferences" trên macOS cũ)

**Ảnh hưởng:**
- Các chỗ gọi `openWindow(id: "settings")` cần đổi sang `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` hoặc `SettingsLink` (macOS 14+)
- Bỏ `id: "settings"` — Settings scene không cần id

### 2. Toggle → Checkbox

**Trước:**
```swift
Toggle("Launch at Login", isOn: $appState.launchAtLogin)
Toggle("Notifications", isOn: $appState.showNotifications)
```

**Sau:**
```swift
Toggle("Launch at Login", isOn: $appState.launchAtLogin)
    .toggleStyle(.checkbox)
Toggle("Notifications", isOn: $appState.showNotifications)
    .toggleStyle(.checkbox)
```

**Lý do:**
- macOS HIG: checkbox cho on/off settings trong form
- Switch style là iOS pattern, trông lạ trên macOS
- Mọi macOS native app (System Settings, Xcode, Finder prefs) đều dùng checkbox

**Áp dụng cho:** Tất cả Toggle trong Settings (hiện có 2: launch at login, notifications)

### 3. TextField số → Stepper

Các field có range cố định chuyển sang `Stepper` — cho phép cả gõ trực tiếp và click +/-.

#### 3a. Debounce (Sync tab)

**Trước:**
```swift
TextField("", value: $appState.debounceSec, format: .number)
    .frame(width: 60)
Text("sec")
Text("(5–300)")
```

**Sau:**
```swift
Stepper(value: $appState.debounceSec, in: 5...300, step: 5) {
    HStack {
        TextField("", value: $appState.debounceSec, format: .number)
            .frame(width: 50)
            .multilineTextAlignment(.trailing)
        Text("sec")
            .foregroundStyle(.secondary)
    }
}
```

**Step:** 5 giây (tăng/giảm mỗi lần 5s — hợp lý cho debounce)

#### 3b. Periodic Sync (Sync tab)

**Sau:**
```swift
Stepper(value: $appState.periodicSyncMin, in: 5...60, step: 5) {
    HStack {
        TextField("", value: $appState.periodicSyncMin, format: .number)
            .frame(width: 50)
            .multilineTextAlignment(.trailing)
        Text("min")
            .foregroundStyle(.secondary)
    }
}
```

**Step:** 5 phút

#### 3c. Keep Logs (App tab)

**Sau:**
```swift
Stepper(value: $appState.keepLogsDays, in: 1...365, step: 1) {
    HStack {
        TextField("", value: $appState.keepLogsDays, format: .number)
            .frame(width: 50)
            .multilineTextAlignment(.trailing)
        Text("days")
            .foregroundStyle(.secondary)
    }
}
```

**Step:** 1 ngày

#### 3d. Bandwidth — Upload/Download (Google Drive tab)

**Trước:**
```swift
TextField("", value: $appState.uploadLimit, format: .number)
    .frame(width: 60)
Text("KB/s")
Text("(0 = unlimited)")
```

**Sau:**
```swift
Stepper(value: $appState.uploadLimit, in: 0...10000, step: 100) {
    HStack {
        TextField("", value: $appState.uploadLimit, format: .number)
            .frame(width: 60)
            .multilineTextAlignment(.trailing)
        Text("KB/s")
            .foregroundStyle(.secondary)
    }
}
Text("0 = unlimited")
    .font(.caption)
    .foregroundStyle(.tertiary)
```

**Step:** 100 KB/s (0, 100, 200, ... — hợp lý cho bandwidth)

### 4. Bỏ hint text `(5–300)` khi dùng Stepper

Stepper đã tự enforce range → không cần hint nữa. Bỏ đi cho gọn:

**Trước:** `Text("(5–300)").font(.caption).foregroundStyle(.tertiary)`
**Sau:** Xóa

Chỉ giữ hint `0 = unlimited` cho bandwidth vì đó là thông tin ngữ nghĩa, không phải range.

### 5. Window sizing

**Trước:**
```swift
// SettingsView
.frame(minWidth: 520, minHeight: 560)

// DriveSyncApp
.defaultSize(width: 580, height: 450)
```

**Sau:**
```swift
// SettingsView — set explicit size cho TabView
.frame(width: 520, height: 480)
```

`Settings` scene tự quản lý window size dựa trên content frame. Không cần `defaultSize` hay `windowResizability`.

## UI Spec sau revamp

### Sync Tab

```
┌───────────────────────────────────────────┐
│  🔄 Sync                                  │
│───────────────────────────────────────────│
│                                           │
│  ┌─ Timing ──────────────────────────┐   │
│  │ Debounce:      [ 30 ]⬍⬆ sec      │   │
│  │ Periodic sync: [ 15 ]⬍⬆ min      │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ File Deletion ──────────────────┐    │
│  │ On file delete: [Move to Trash ▾]│    │
│  └────────────────────────────────────┘   │
│                                           │
└───────────────────────────────────────────┘
```

### App Tab

```
┌───────────────────────────────────────────┐
│  ⚙ App                                    │
│───────────────────────────────────────────│
│                                           │
│  ┌─ Section ─────────────────────────┐   │
│  │ ☑ Launch at Login                 │   │
│  │ ☑ Notifications                   │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section ─────────────────────────┐   │
│  │ Symlink: [ ~/Drive           ]    │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ┌─ Section ─────────────────────────┐   │
│  │ Log level: [ info ▾ ]            │   │
│  │ Keep logs: [ 30 ]⬍⬆ days        │   │
│  └────────────────────────────────────┘   │
│                                           │
│  ─────────────────────────────────────    │
│  Logs (live)              [⏸ Pause]      │
│  ┌─ monospace, dark bg ────────────┐     │
│  │ 14:32  ✓  Sync complete (3)    │     │
│  │ ...                             │     │
│  └─────────────────────────────────┘     │
│  [Open Log File]                          │
│                                           │
└───────────────────────────────────────────┘
```

### Google Drive Tab — Bandwidth section

```
┌─ Bandwidth ──────────────────────────┐
│ Upload:   [    0 ]⬍⬆ KB/s           │
│           0 = unlimited ← caption    │
│ Download: [    0 ]⬍⬆ KB/s           │
│           0 = unlimited ← caption    │
└────────────────────────────────────────┘
```

## Files cần sửa

| File | Thay đổi |
|------|----------|
| `DriveSyncApp.swift` | `Window("Settings")` → `Settings` scene. Fix nơi gọi `openWindow(id: "settings")`. |
| `SettingsView.swift` | Bỏ `minWidth/minHeight`, set `frame(width:height:)` trực tiếp. |
| `AppTab.swift` | Toggle → `.checkbox`. Keep logs TextField → Stepper. |
| `SyncTab.swift` | Debounce + periodic TextField → Stepper. Bỏ hint text. |
| `GoogleDriveTab.swift` | Bandwidth TextField → Stepper. Giữ `0 = unlimited` hint. |
| `MenuDropdownView.swift` | Nếu có `openWindow(id: "settings")` → đổi cách mở Settings. |

## Ảnh hưởng đến code khác

### Mở Settings window

`Settings` scene không dùng `openWindow(id:)`. Cách mở:

```swift
// macOS 14+: dùng SettingsLink trong SwiftUI
SettingsLink {
    Text("Open Settings")
}

// Hoặc programmatic:
if #available(macOS 14, *) {
    SettingsLink { ... }
} else {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
```

Cần check `MenuDropdownView` xem có button nào mở Settings không → đổi sang `SettingsLink`.

## Không thay đổi

- Config persistence (ConfigManager + didSet) — giữ nguyên
- Tab structure (4 tabs) — giữ nguyên
- Tab style (`.sidebarAdaptable`) — giữ nguyên
- Form style (`.grouped`) — giữ nguyên
- Google Drive tab layout (ngoài bandwidth) — giữ nguyên
- Drives tab — giữ nguyên

## Acceptance Criteria

- [ ] ⌘, mở Settings window
- [ ] Menu "Settings..." xuất hiện trong app menu
- [ ] Chỉ 1 instance Settings window được mở
- [ ] Toggle hiển thị checkbox style
- [ ] Stepper cho debounce: range 5–300, step 5
- [ ] Stepper cho periodic: range 5–60, step 5
- [ ] Stepper cho keep logs: range 1–365, step 1
- [ ] Stepper cho bandwidth: range 0–10000, step 100
- [ ] Không còn hint `(5–300)`, `(5–60)` — Stepper tự enforce
- [ ] Giữ hint `0 = unlimited` cho bandwidth
- [ ] Tất cả giá trị vẫn persist đúng vào config.toml
- [ ] Settings mở từ menu dropdown vẫn hoạt động

---

## ✅ Implementation Status

**Fully implemented** — 2026-03-09

| Item | Status |
|------|--------|
| `Settings` scene (⌘, support, single instance) | ✅ Done |
| Toggle → `.checkbox` style | ✅ Done |
| TextField số → Stepper (debounce, periodic, keep logs, bandwidth) | ✅ Done |
| Removed hint text `(5-300)` etc. | ✅ Done |
| Window sizing `.frame(width: 520, height: 480)` | ✅ Done |
| MenuDropdownView opens Settings correctly | ✅ Done |

---

**Author:** Claude (Minh Thư) — 2026-03-09
