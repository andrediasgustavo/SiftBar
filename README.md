# SiftBar

[![CI](https://github.com/andrediasgustavo/SiftBar/actions/workflows/ci.yml/badge.svg)](https://github.com/andrediasgustavo/SiftBar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/andrediasgustavo/SiftBar)](https://github.com/andrediasgustavo/SiftBar/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Your Mac, explained before it changes.**

SiftBar is a macOS menu bar app that shows you what is running, what starts with
your Mac, and what is taking up space — then lets you choose what to clean up.
Every finding comes with a plain-language explanation, its evidence, and the
exact command SiftBar will run. Nothing happens without your confirmation.

[**Download for macOS**](https://github.com/andrediasgustavo/SiftBar/releases/latest/download/SiftBar.dmg)
· [How it works](#how-it-works) · [Build from source](#for-developers)

![SiftBar overview](docs/screenshots/overview.png)

## What's new in 0.4.0

- **Instant removal after every action.** Succeeded items leave the Overview,
  Disk, and Caches views immediately — no waiting for the next scan. Rows are
  matched by ID and path, so a scan that raced the Trash move cannot bring a
  deleted item back.
- **Quick refresh, background space map.** After applying actions, the list
  and counts update in a couple of seconds, then the slow space map and large
  file walk catch up in the background without freezing the dashboard.
- **No acting on stale rows.** While a scan or an action batch is running,
  checkboxes, quick actions, and Apply are disabled so an outdated row cannot
  be run twice. Finder reveal and navigation stay available.
- Deleted paths are tombstoned briefly; if an app recreates a cache, it
  reappears with its real, freshly measured size on the next scan.

## What's new in 0.3.1

- New documentation screenshots generated from synthetic demo data.
- Disk quick actions now appear only on the row where they apply.
- The confirmation sheet no longer repeats the same warning twice.
- Added a hidden `--demo` mode for reproducible README screenshots.

## What's new in 0.3.0

- **Memory and Disk are separate dashboards.** Memory uses the same
  app/wired/compressed definition as Activity Monitor; Disk matches System
  Settings and explains APFS volumes.
- **The Disk tab is actionable.** It combines the space map with a **Clean up**
  list of caches and reviewed leftovers, with checkboxes and command previews.
  **Show details / Hide details** collapses the map when you need more room.
- **Caches are itemized per app**, with a warning when the app is still running.
- **Protected system processes** are labelled `Protected`, excluded from the
  review count, and offer Activity Monitor instead of a dead end.
- **Safer leftovers.** iCloud/Apple folders such as `CloudDocs` and
  `FileProvider` are never offered for deletion; the remaining leftovers are
  shown as user data that needs review.
- **One-time, optional permission onboarding** for Full Disk Access, with the
  app continuing normally if you choose **Not now**.

## What it does

- **Memory** — an Activity Monitor-style breakdown (app, wired, compressed,
  cached, free), swap and pressure, plus the apps using the most RAM with a
  one-click Quit. Memory numbers never get mixed with disk numbers.
- **Disk** — container-level usage that matches System Settings, a measured
  space map, APFS volume breakdown (macOS, Preboot, Recovery, VM, Data), and a
  **Clean up** list of caches and reviewed leftovers. The map collapses with
  **Show details / Hide details**, so the actionable list gets the space.
- **Startup & login items** — see the launch agents and daemons that start with
  your Mac, and disable the ones you do not recognize.
- **Heavy processes** — helpers are grouped under the app they belong to, so
  Chrome, VS Code, and Spotify appear once with their real total. Protected
  macOS processes are labelled `Protected`, excluded from the review count, and
  offer Activity Monitor instead of a dead-end warning.
- **Caches** — one row per app cache, with a warning when the app is still
  running. Moving a cache to the Trash is transparent and reversible.
- **Leftovers** — Application Support data from apps that are no longer
  installed. SiftBar shows the size, explains that it is user data, and only
  moves it to the Trash after confirmation.
- **Biggest consumers** — see the largest files and folders in Downloads,
  Desktop, and Documents, and reveal them in Finder.
- **Clear explanations** — every row shows its impact, its source, and a risk
  label (`Safe`, `Caution`, or `Dangerous`). Informational rows are labelled
  `Info` and never counted as findings.

## How it works

1. **Analyze** — a read-only scan of memory, processes, startup items, services,
   disk, caches, and leftovers.
2. **Review** — findings are sorted by risk, so red and orange items come first.
   Search, filter by risk, and open a folder in Finder from its row.
3. **Apply** — select the items you want, review the exact commands, and
   confirm. SiftBar rescans and shows what moved to the Trash or which RAM was
   released.
4. **See the result** — a result card separates disk bytes moved to the Trash
   from RAM released by quitting apps. Empty the Trash to actually free disk
   space.

## See it in action

### Everything in one triage list

![SiftBar overview](docs/screenshots/overview.png)

Each row shows the risk, the title, the impact, a short explanation, and the
source. Quick actions appear where they make sense: **Quit** for an app,
**Review** for a leftover. Informational rows are labelled `Info` and protected
macOS processes are labelled `Protected`; neither counts as a finding.

### Memory, explained like Activity Monitor

![Memory dashboard](docs/screenshots/memory.png)

The Memory tab uses the same app/wired/compressed definition as Activity
Monitor. It shows pressure, swap, a proportional breakdown, and the apps using
the most RAM with a one-click **Quit**. Memory numbers are never mixed with disk
numbers.

### Disk: where space goes and what you can clean

![Disk clean-up list](docs/screenshots/disk.png)

The Disk tab combines the space map with a **Clean up** list of caches and
reviewed leftovers, with checkboxes and command previews. **Show details /
Hide details** collapses the map so the actionable list gets more room.

![Disk map and APFS volumes](docs/screenshots/disk-details.png)

Expanded, the map shows the measured folders, APFS volume breakdown, and the
part of `Used` that SiftBar will not touch. "System & other" is macOS, protected
data, snapshots and shared APFS blocks — not a cleanup target.

### Startup & Login

![Startup and login items](docs/screenshots/startup.png)

User launch agents can be disabled. System-wide daemons are shown with a lock
because they require administrator rights; SiftBar will not touch them.

### Confirmation, not automation

![Confirmation sheet](docs/screenshots/confirmation.png)

The confirmation sheet lists the exact commands for every selected item. No
bulk "clean everything" button, no hidden actions.

### A receipt for your cleanup

![Cleanup result](docs/screenshots/result.png)

*Example result from synthetic demo data.* SiftBar reports disk bytes moved to
the Trash separately from RAM released by quitting apps, and reminds you to
empty the Trash to actually free the space.

### One optional permission, not a wall of prompts

![Full Disk Access onboarding](docs/screenshots/access.png)

macOS protects Desktop, Documents and Downloads separately. The first time you
open the dashboard, SiftBar explains what is missing and offers one optional
Full Disk Access grant. Choose **Not now** and the app keeps working with a
partial disk map; a small note in the Disk tab lets you complete access later.
No repeated folder prompts.

*Screenshots use synthetic demo data (`--demo`); no real user paths or apps.*

## Safe by design

- **Read-only by default.** Analyze never changes anything.
- **No "clean everything" button.** Every action is item by item.
- **Full transparency.** The command is shown before it runs.
- **Never touches SIP-protected paths** such as `/System` and `AssetsV2`.
- **Protected processes are never actionable.** They are labelled `Protected`,
  excluded from the review count, and offer Activity Monitor instead of a
  kill action.
- **Only whitelisted cache paths can be moved to the Trash.** The executor
  checks again before acting, including path traversal and symlink escapes.
- **System-wide launch items stay locked** unless SiftBar has administrator
  support (planned, optional).
- **No account, no telemetry, no network calls.** SiftBar works locally.

## Install

1. Download the latest **[SiftBar.dmg](https://github.com/andrediasgustavo/SiftBar/releases/latest/download/SiftBar.dmg)**.
2. Open the DMG and drag **SiftBar** into **Applications**.
3. Eject the DMG. SiftBar runs in the menu bar — look for the filter icon.
   There is no Dock icon.

**Requirements:** macOS 13 or later on Apple Silicon.

### First launch: the macOS security prompt

SiftBar is **ad-hoc signed and not notarized yet**, so macOS blocks it the
first time. This is expected, and you only need to approve it once.

**macOS 15 (Sequoia) and later**

1. Open **Applications** and double-click **SiftBar**. macOS shows a warning;
   click **Done** (not **Move to Trash**).
2. Open **System Settings → Privacy & Security** and scroll down to
   **Security**.
3. Find the message about SiftBar and click **Open Anyway**.
4. Authenticate with Touch ID or your password, then click **Open** in the
   final dialog.

**macOS 13 and 14**

1. Open **Applications**, right-click **SiftBar**, and choose **Open**.
2. Click **Open** in the confirmation dialog.

After this first approval, a normal double-click opens SiftBar. Do **not**
disable Gatekeeper globally or run `spctl --master-disable`.

<details>
<summary>Advanced: removing the quarantine attribute</summary>

If the dialogs above are unavailable (for example, on a machine managed by
MDM), you can remove the quarantine flag from the app you just installed:

```bash
xattr -dr com.apple.quarantine /Applications/SiftBar.app
```

Only do this if you downloaded the DMG from this repository and trust it.
This bypasses Gatekeeper's first-launch check; it is not required for normal
installations.
</details>

### One permission instead of three

macOS protects **Desktop**, **Documents** and **Downloads** separately, so a
naive scan triggers three different permission prompts. macOS has no API to
combine them; **Full Disk Access** is the single consent that covers all three.

Without Full Disk Access, SiftBar skips those three folders. The first time
you open the dashboard it shows a one-time, optional sheet explaining what is
missing; the app keeps working normally if you choose **Not now**. A small
**Partial disk map** note stays in the Disk tab so you can complete access later.

1. In the sheet, click **Open Full Disk Access**.
2. Enable **SiftBar** in **System Settings → Privacy & Security → Full Disk
   Access**.
3. Return to SiftBar and click **Check again**. If the permission does not take
   effect immediately, quit SiftBar from the menu bar and open it again.

Prefer not to grant Full Disk Access? Open **Other ways to grant access → Use
folder prompts instead**. macOS will then ask once per protected folder, and
SiftBar remembers your choice.

SiftBar never asks for administrator rights or runs `sudo`.


## Usage

1. Click the waveform icon in the menu bar.
2. Choose **Open Dashboard** (`⌘D`) or **Run Analysis** (`⌘R`).
3. Press **Analyze** and review the findings. The scan is read-only.
4. Filter by risk, search across titles/details/evidence, or use the folder
   button to reveal a path in Finder.
5. Grouped processes show a chevron; expand the row to quit a specific PID.
   Disabled launch items appear as **Disabled launch item** and can be enabled
   again.
6. Open **Disk** to see the space map, APFS volumes, largest files and folders,
   and the **Clean up** list of caches and reviewed leftovers — all actionable
   from the same tab. Use **Show details / Hide details** to collapse the map
   and give the cleanup list more room; SiftBar remembers your choice. Large
   files are read-only; use the folder button to review them in Finder.
7. Select changeable items with the checkboxes, then use the action bar at the
   bottom.
8. Review the commands and confirm. SiftBar runs them, rescans, and shows the
   result.
9. Open **History** (`⌘Y`) to see previous actions; `⌘R` runs a new analysis
   and `⌘F` focuses search.
10. Press **Quit SiftBar** (`⌘Q`) to exit.

---

# For developers

## Build from source

```bash
git clone https://github.com/andrediasgustavo/SiftBar.git
cd SiftBar
./scripts/run.sh
```

`run.sh` builds a release binary, assembles `dist/SiftBar.app`, signs it
ad-hoc, and launches it.

### Build commands

| Command | Result |
|---|---|
| `./scripts/run.sh` | Build (release), bundle, sign, and launch |
| `./scripts/run.sh debug` | Same, with an unoptimized debug build |
| `./scripts/build.sh` | Build `dist/SiftBar.app` without launching |
| `./scripts/build.sh debug` | Debug build without launching |
| `./scripts/test.sh` | Run the full XCTest suite without Xcode (local fallback) |
| `./scripts/package.sh` | Build `dist/SiftBar.dmg` from the app bundle |
| `./scripts/clean.sh` | Remove `.build/` and `dist/` |
| `swift scripts/make-icon.swift Resources/AppIcon.icns` | Regenerate the app icon |
| `swift build` | Build through SwiftPM (requires a working toolchain) |
| `swift test` | Run unit tests (requires full Xcode) |

> **Toolchain note:** the SwiftPM manifest loader in some Command Line Tools
> installations fails to link `PackageDescription`. The scripts therefore
> invoke `swiftc` directly. `Package.swift` is kept for toolchains where
> SwiftPM works normally, including the GitHub Actions runners.

### Requirements

| Requirement | Notes |
|---|---|
| macOS 13 or later | Apple Silicon only in v1 |
| Swift 5.9+ | Swift 6.x toolchains work |
| Command Line Tools | `swiftc`, `codesign`, `plutil`, `hdiutil` |
| Full Xcode | Only needed to run `swift test` locally; the app builds with Command Line Tools |

## Configuration

SiftBar is configured at build time; there is no runtime settings file yet.
Use the table below to find where each value lives.

| Setting | Default | Where to change it |
|---|---|---|
| Bundle identifier | `com.andredias.siftbar` | `Resources/Info.plist` → `CFBundleIdentifier` |
| Display name | `SiftBar` | `Resources/Info.plist` → `CFBundleDisplayName` / `CFBundleName` |
| Version | `0.3.1` (build `6`) | `Resources/Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion` |
| Minimum macOS | `13.0` | `Resources/Info.plist` → `LSMinimumSystemVersion`, `Package.swift` → `.macOS(.v13)`, `scripts/build.sh` → `-target` |
| Menu bar only | enabled | `Resources/Info.plist` → `LSUIElement` |
| Build configuration | `release` | First argument to `scripts/build.sh` / `scripts/run.sh` (`release` or `debug`) |
| CPU architecture | `arm64` | `scripts/build.sh` → `-target arm64-apple-macos13.0` |
| Output location | `dist/SiftBar.app` | `scripts/build.sh` → `APP_DIR` |
| Signing | ad-hoc (`codesign -s -`) | `scripts/build.sh` → final `codesign` call; use a Developer ID for distribution |

Runtime data:

| Data | Path |
|---|---|
| History | `~/Library/Application Support/SiftBar/history.json` |
| Logs | `~/Library/Logs/SiftBar/` (planned) |

## Tests and CI

Unit tests live in `Tests/SiftBarTests/` and use XCTest. With full Xcode, run:

```bash
swift test
```

On a Command Line Tools-only machine, use the local fallback:

```bash
./scripts/test.sh
```

It compiles a small XCTest-compatible module, builds the app as a testable
library, generates a runner from every `func test…`, and executes the same
suite without `XCTest.framework` or SwiftPM.

### Screenshot mode

README images are generated from synthetic data, so they never expose a real
user's paths or apps:

```bash
./scripts/build.sh release
dist/SiftBar.app/Contents/MacOS/SiftBar --demo
dist/SiftBar.app/Contents/MacOS/SiftBar --demo --demo-access
dist/SiftBar.app/Contents/MacOS/SiftBar --demo --demo-confirmation
dist/SiftBar.app/Contents/MacOS/SiftBar --demo --demo-result
```

The suite has 246 tests covering command execution (including output larger
than a pipe buffer), every parser (`vm_stat`, `top`, swap, `df`, `ps`,
`launchctl`, `brew services`, `du`), risk thresholds, protected-process rules,
duplicate detection, app-level process grouping, per-PID children, filtering,
search, sorting, action previews, selection rules, disabled/enabled launch
labels, disk/memory metric separation, space-map grouping, history storage,
cleanup whitelist enforcement (including traversal and symlink escapes),
largest-consumer ranking, per-app cache detection, running-app warnings, and a
live read-only scan, APFS volume parsing, protected-process classification, and memory/disk separation.

The GitHub Actions workflow at `.github/workflows/ci.yml` runs on every push
and pull request to `main`:

1. **Build and test** — `swift build`, `swift build -c release`, and
   `swift test --parallel` on `macos-15`.
2. **Validate** — shell syntax checks, `plutil -lint`, a full
   `scripts/build.sh release`, bundle structure and `LSUIElement` checks,
   `codesign --verify`, DMG packaging, and a check of the signed app inside the
   DMG. The `.app` and `.dmg` are uploaded as workflow artifacts.

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds the app,
packages the DMG, verifies it, and publishes `SiftBar.dmg` on the GitHub
Release for that tag.

## Project layout

```
Sources/SiftBar/
├── App/          # entry point, state, dashboard window
├── Core/         # models, command runner, probes, filters, executor, history
├── Collectors/   # memory, processes, startup, services, disk, caches, big consumers
├── UI/           # dashboard, rows, menu content, confirmation, history
└── Support/      # path sizing
Resources/        # Info.plist (LSUIElement = true) and AppIcon.icns
Tests/            # XCTest unit tests
scripts/          # build, run, clean, package
docs/screenshots/ # README screenshots
.github/          # CI and release workflows
```

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 0 | Skeleton, menu bar, build pipeline, read-only probe | ✅ |
| 1 | Collectors: memory, processes, startup, brew, disk, caches, leftovers | ✅ |
| 2 | Risk classification, process grouping, filters, and search | ✅ |
| 3 | Safe actions with preview (processes, launchctl, brew services) | ✅ per-PID and enable; login items pending |
| 4 | Cache and disk cleanup with whitelist | ✅ |
| 5 | Optional privileged helper for system-level actions | ⏸ blocked on Developer ID |
| 6 | History, menu commands, scheduling, notifications, icon | ⏳ history and shortcuts done |
| 7 | Distribution: DMG and GitHub Releases | ✅ notarization pending |

The detailed plan, architecture, guardrails, and acceptance criteria live in
[`PLAN.md`](PLAN.md).

## Contributing

1. Create a branch from `main`.
2. Keep changes read-only by default and document any command an action runs.
3. Run `swift test` and `./scripts/build.sh` before opening a pull request.
4. Describe the behavior change and how you tested it.

## License

Released under the [MIT License](LICENSE). © 2026 André Dias.
