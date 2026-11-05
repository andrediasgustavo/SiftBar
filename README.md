# SiftBar

A macOS menu bar app that **analyzes your system, explains what it finds, and lets you choose what to clean up** — nothing runs without confirmation.

> **Status:** Phase 0 — app skeleton and build pipeline. The analysis engine lands in Phase 1.

## Why

Most "Mac cleaners" make opaque decisions and act on their own. SiftBar is the opposite:

1. **Analyze** — read-only scan of memory, swap, processes, startup items, services, disk, caches and leftovers.
2. **Review** — every item shows what it is, its impact, the evidence, and a risk badge (`Safe` / `Caution` / `Dangerous`).
3. **Apply** — you select items; the app previews the exact command and waits for confirmation.

## Principles

- Read-only by default.
- No "clean everything" button.
- Full transparency: source and command for every action.
- Never touches SIP-protected paths (`/System`, `AssetsV2`, etc.).
- No placebo "free up RAM" feature.

## Requirements

- macOS 13 or later (Apple Silicon)
- Command Line Tools with Swift 5.9+ — **Xcode is not required**
- `swift --version`, `codesign` and `plutil` available

## Build and run

```bash
./scripts/run.sh              # build release, bundle, ad-hoc sign, launch
./scripts/build.sh            # build release -> dist/SiftBar.app
./scripts/build.sh debug      # unoptimized build with debug symbols
./scripts/clean.sh            # remove .build and dist
```

The app has no Dock icon. Look for the waveform icon in the menu bar.

> **Toolchain note:** the SwiftPM manifest loader in some Command Line Tools
> installations fails to link `PackageDescription`. The scripts therefore
> invoke `swiftc` directly. `Package.swift` is kept for toolchains where
> SwiftPM works normally.

## Project layout

```
Sources/SiftBar/
├── App/          # entry point, state, dashboard window
├── Core/         # command runner, system probe (future: analyzers, executor)
├── Collectors/   # Phase 1
├── UI/           # SwiftUI views
└── Support/      # formatters and logging
Resources/        # Info.plist (LSUIElement = true)
scripts/          # build, run, clean
```

## Roadmap

| Phase | Scope |
|---|---|
| 0 | Skeleton, menu bar, build pipeline, read-only probe |
| 1 | Collectors: memory, processes, startup, brew, disk, caches, leftovers |
| 2 | Risk classification and review UI |
| 3 | Safe actions with preview (login items, launchctl, brew services) |
| 4 | Cache and disk cleanup with whitelist |
| 5 | Optional privileged helper for system-level actions |
| 6 | History, scheduling, notifications, icon |

The detailed plan lives in [`PLAN.md`](PLAN.md) (Portuguese).

## License

TBD.
