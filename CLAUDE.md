# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**DriveSync** — macOS app that auto-syncs external drives with Google Drive as a central hub. Multiple physical drives (same volume name) at different locations stay in sync via cloud. Vietnamese-language project docs.

## Architecture

Single Swift app with 3 layers:

- **Core Library** — All logic, no UI. Testable independently.
  - `SyncEngine` — wraps rclone bisync
  - `MountDetector` — DiskArbitration framework for plug/unplug detection
  - `FileWatcher` — FSEvents for real-time file change monitoring
  - `ConflictHandler` — keeps both versions (`file.conflict-YYYYMMDD`)
  - `ConfigManager` — TOML config at `~/.config/drivesync/config.toml`
- **CLI** — thin wrapper over Core (`drivesync sync|status|eject|doctor|setup|pause|resume|log`)
- **Menubar UI** — SwiftUI, thin wrapper over Core

No separate daemon — CLI and Menubar share the same Core library and binary.

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (menubar only)
- **Sync:** rclone (called as subprocess, bisync mode)
- **Mount detection:** DiskArbitration (macOS framework)
- **File watching:** FSEvents (macOS native)
- **Config format:** TOML
- **Testing:** XCTest

## State Machine

```
IDLE →(mount)→ SYNCING →(done)→ WATCHING
                 ↓                  ↓
              RETRYING      DEBOUNCING(30s)
                 ↓                  ↓
              SYNCING ←─────────────┘

Any state →(unmount)→ IDLE
```

## Sync Flow

1. Drive plugged → DiskArbitration detects mount
2. Create symlink `~/Drive` → `/Volumes/ZORRO`
3. Full bisync with Google Drive via rclone
4. FSEvents monitors for changes → debounce 30s → incremental sync
5. Every 15 min → full bisync (catches Google Drive-side changes)
6. Drive unplugged → stop watcher, remove symlink

## Development Slices

The project follows feature slices (see `docs/TECHNICAL.md`). Current status: **pre-code** — only design docs exist. Start with Slice 0 (app skeleton, rclone check, Core structure, XCTest setup, CLI arg parsing).

## Running the App

Mỗi lần start app, phải kill process DriveSync cũ trước:
```bash
pkill -x DriveSync; sleep 0.5; open .build/debug/DriveSync
```

## Build & Test Commands

```bash
# Build (once Xcode project exists)
swift build
swift test

# Run CLI
swift run drivesync <command>

# Xcode
xcodebuild -scheme DriveSync -destination 'platform=macOS' build
xcodebuild -scheme DriveSync -destination 'platform=macOS' test
```

## Documentation Structure

```
docs/
├── design/          — UI mockups, icon prompts, config format
│   ├── UI_DESIGN.md
│   ├── ICON_PROMPTS.md
│   └── CONFIG.md
├── prd/             — Product Requirements Documents (viết trước khi code)
│   ├── PRD-001_Google_Drive_Connection.md
│   ├── PRD-002_Rclone_Communication.md
│   ├── PRD-003_Sync_Settings.md
│   ├── PRD-004_Settings_UI_Revamp.md
│   └── PRD-005_Logging_System.md
├── testing/         — Test plans
│   └── TEST-001_Google_Drive_Connection.md
├── TECHNICAL.md     — Architecture & development slices
└── USER_STORIES.md  — User stories & acceptance criteria
```

Root giữ: `README.md`, `CLAUDE.md`

## Workflow Rule

**PHẢI viết PRD trước khi code.** Mọi chức năng mới đều cần file PRD (Product Requirements Document) được review và approve trước khi bắt tay vào implement. Không skip bước này.

## Logging Rule

**Mọi feature mới PHẢI có logging.** Khi implement bất kỳ chức năng nào, luôn thêm log entries qua `LogManager.shared`:
- Các event quan trọng (bắt đầu, thành công, thất bại) → `info` hoặc `error`
- Debug data (token expiry, raw response) → `debug`
- Recoverable issues (retry, fallback) → `warn`
- Gọi trong async context: `await LogManager.shared.info("...")`
- Gọi trong `didSet` (sync context): `Task { await LogManager.shared.info("...") }`

Xem PRD-005 (`docs/prd/PRD-005_Logging_System.md`) để biết format và conventions.

## Key Design Decisions

- rclone is an external dependency (not bundled) — `drivesync doctor` verifies it
- Config lives at `~/.config/drivesync/config.toml`
- Volume name defaults to "ZORRO" — all physical drives share this name
- Conflicts never overwrite — both versions kept
- Offline changes queued, synced when network returns
