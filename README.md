# SiftBar

[![CI](https://github.com/andrediasgustavo/SiftBar/actions/workflows/ci.yml/badge.svg)](https://github.com/andrediasgustavo/SiftBar/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A macOS menu bar app that **analyzes your system, explains what it finds, and
lets you choose what to clean up** — nothing runs without confirmation.

> **Status:** Phase 1 — read-only collectors and review list. Actions land in Phase 3.

## Why

Most "Mac cleaners" make opaque decisions and act on their own. SiftBar is the
opposite:

1. **Analyze** — read-only scan of memory, swap, processes, startup items,
   services, disk, caches, and leftovers.
2. **Review** — every item shows what it is, its impact, the evidence, and a
   risk badge (`Safe` / `Caution` / `Dangerous`).
3. **Apply** — you select items; the app previews the exact command and waits
   for confirmation.

### Principles

- Read-only by default.
- No "clean everything" button.
- Full transparency: source and command for every action.
- Never touches SIP-protected paths (`/System`, `AssetsV2`, etc.).
- No placebo "free up RAM" feature.

## Requirements

| Requirement | Notes |
|---|---|
| macOS 13 or later | Apple Silicon only in v1 |
| Swift 5.9+ | Swift 6.x toolchains work |
| Command Line Tools | `swiftc`, `codesign`, `plutil` |
| Full Xcode | Only needed to run `swift test` locally; the app itself builds with Command Line Tools |

## Install and run

```bash
git clone https://github.com/andrediasgustavo/SiftBar.git
cd SiftBar
./scripts/run.sh
```

`run.sh` builds a release binary, assembles `dist/SiftBar.app`, signs it
ad-hoc, and launches it. SiftBar has no Dock icon — look for the waveform icon
in the menu bar.

### Build commands

| Command | Result |
|---|---|
| `./scripts/run.sh` | Build (release), bundle, sign, and launch |
| `./scripts/run.sh debug` | Same, with an unoptimized debug build |
| `./scripts/build.sh` | Build `dist/SiftBar.app` without launching |
| `./scripts/build.sh debug` | Debug build without launching |
| `./scripts/clean.sh` | Remove `.build/` and `dist/` |
| `swift build` | Build through SwiftPM (requires a working toolchain) |
| `swift test` | Run unit tests (requires full Xcode) |

> **Toolchain note:** the SwiftPM manifest loader in some Command Line Tools
> installations fails to link `PackageDescription`. The scripts therefore
> invoke `swiftc` directly. `Package.swift` is kept for toolchains where
> SwiftPM works normally, including the GitHub Actions runners.

## Usage

1. Click the waveform icon in the menu bar.
2. Choose **Open Dashboard** (`⌘D`) for the full window, or **Run Analysis**
   (`⌘R`) directly from the menu.
3. Press **Analyze**. The scan is read-only: it collects totals and reports
   the current state without changing anything.
4. Press **Quit SiftBar** (`⌘Q`) to exit.

To open the dashboard at launch during development:

```bash
open dist/SiftBar.app --args --show-dashboard
open dist/SiftBar.app --args --show-dashboard --analyze
```

## Configuration

SiftBar is configured at build time; there is no runtime settings file yet.
Use the table below to find where each value lives.

| Setting | Default | Where to change it |
|---|---|---|
| Bundle identifier | `com.andredias.siftbar` | `Resources/Info.plist` → `CFBundleIdentifier` |
| Display name | `SiftBar` | `Resources/Info.plist` → `CFBundleDisplayName` / `CFBundleName` |
| Version | `0.1.0` (build `1`) | `Resources/Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion` |
| Minimum macOS | `13.0` | `Resources/Info.plist` → `LSMinimumSystemVersion`, `Package.swift` → `.macOS(.v13)`, `scripts/build.sh` → `-target` |
| Menu bar only | enabled | `Resources/Info.plist` → `LSUIElement` |
| Build configuration | `release` | First argument to `scripts/build.sh` / `scripts/run.sh` (`release` or `debug`) |
| CPU architecture | `arm64` | `scripts/build.sh` → `-target arm64-apple-macos13.0` |
| Output location | `dist/SiftBar.app` | `scripts/build.sh` → `APP_DIR` |
| Signing | ad-hoc (`codesign -s -`) | `scripts/build.sh` → final `codesign` call (replace with a Developer ID for distribution) |

Planned runtime locations (Phase 3+):

| Data | Path |
|---|---|
| History | `~/Library/Application Support/SiftBar/history.json` |
| Logs | `~/Library/Logs/SiftBar/` |

The app is not sandboxed. If macOS blocks reading a protected directory, grant
SiftBar **Full Disk Access** in System Settings → Privacy & Security.

## Tests and CI

Unit tests live in `Tests/SiftBarTests/` and use XCTest. Run them with:

```bash
swift test
```

The suite covers command execution, every parser (`vm_stat`, swap, `df`,
`ps`, `launchctl`, `brew services`, `du`), risk thresholds, duplicate
detection, sorting, and a live read-only scan.

The GitHub Actions workflow at `.github/workflows/ci.yml` runs on every push
and pull request to `main`:

1. **Build and test** — `swift build`, `swift build -c release`, and
   `swift test --parallel` on `macos-15`.
2. **Validate** — shell syntax checks, `plutil -lint` on `Info.plist`, a full
   `scripts/build.sh release`, bundle structure and `LSUIElement` checks, and
   `codesign --verify`. The signed `.app` is uploaded as a workflow artifact.

## Project layout

```
Sources/SiftBar/
├── App/          # entry point, state, dashboard window
├── Core/         # command runner, system probe (future: analyzers, executor)
├── Collectors/   # Phase 1
├── UI/           # SwiftUI views
└── Support/      # formatters and logging
Resources/        # Info.plist (LSUIElement = true)
Tests/            # XCTest unit tests
scripts/          # build, run, clean
.github/          # CI workflow
```

## Roadmap

| Phase | Scope |
|---|---|
| 0 | Skeleton, menu bar, build pipeline, read-only probe ✅ |
| 1 | Collectors: memory, processes, startup, brew, disk, caches, leftovers ✅ |
| 2 | Risk classification and review UI |
| 3 | Safe actions with preview (login items, launchctl, brew services) |
| 4 | Cache and disk cleanup with whitelist |
| 5 | Optional privileged helper for system-level actions |
| 6 | History, scheduling, notifications, icon |

The detailed plan lives in [`PLAN.md`](PLAN.md) (Portuguese).

## Contributing

1. Create a branch from `main`.
2. Keep changes read-only by default and document any command an action runs.
3. Run `swift test` and `./scripts/build.sh` before opening a pull request.
4. Describe the behavior change and how you tested it.

## License

Released under the [MIT License](LICENSE). © 2026 André Dias.
