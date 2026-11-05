# SiftBar — Implementation Plan

> A macOS menu bar app that **analyzes** the system, presents an **explained
> list** of findings, and **applies only what you choose** — with command
> previews and risk classification.

- **Name:** SiftBar (checked on 2026-11-04: no conflicting app/product; `.app`
  name available; no relevant GitHub project)
- **Project folder:** `~/Documents/SiftBar`
- **Provisional bundle ID:** `com.andredias.siftbar`
- **Minimum target:** macOS 13.0+ (Apple Silicon; Intel is not a priority)
- **Language:** code, comments, documentation, and UI are English
- **Status:** Phases 0–4 complete; Phase 6 partially complete. See §8.

---

## 1. Goal

Reproduce, safely, the manual cleanup work done in the original session, in a
three-step flow:

1. **Analyze** — read-only scan of memory, swap, processes, startup items,
   services, disk, caches, and leftovers.
2. **Review** — every item shows a title, detail, impact (MB/GB or RAM), the
   **source of the finding**, and a risk label: `Safe` / `Caution` / `Dangerous`.
3. **Apply** — you select items; the app shows the **exact command** and runs it
   only after confirmation. Nothing is automatic by default.

### Principles

- **Read-only by default.** The Analyze button never changes anything.
- **No "clean everything" button.** Every action is item by item and reversible
  when possible.
- **Full transparency.** Every row shows where the finding came from and what
  will run.
- **No placebo.** Focus on causes (agents, login items, heavy apps), not
  "freeing RAM".
- **Never touch SIP-protected areas** (`/System`, `AssetsV2`, etc.).
- **Critical processes are never actionable.** Protected system processes are
  classified as dangerous and cannot be terminated from SiftBar.

### Out of scope (v1)

- Removing or cleaning `AssetsV2` and any SIP-protected path.
- "RAM optimization" with `purge` (cosmetic).
- Killing processes automatically or in bulk.
- Mac App Store / sandboxing (incompatible with the product's purpose).
- Intel support and macOS < 13.

---

## 2. Verified environment

| Item | Result |
|---|---|
| macOS | 27.2 (build 26B123) locally; CI runs macOS 15 |
| Full Xcode | ❌ not installed locally |
| Command Line Tools | ✅ `/Library/Developer/CommandLineTools` |
| Swift | 6.4.2 (arm64) locally |
| SDK | MacOSX 27.2 |
| `MenuBarExtra` (SwiftUI) | ✅ compiles with direct `swiftc` |
| Tools | `codesign`, `plutil`, `iconutil`, `hdiutil` available |

**Consequence:** local builds use **direct `swiftc` + packaging scripts**, without
Xcode. The SwiftPM shipped with this CLT installation is broken (the
`PackageDescription` manifest fails to link), so `scripts/build.sh` compiles the
sources directly; `Package.swift` is kept for healthy toolchains and CI.

Local signing is **ad-hoc** (`codesign -s -`). Release DMGs are ad-hoc signed
too, so first launch requires the standard Gatekeeper override. Distribution
with Developer ID + notarization is planned once a signing identity exists.

---

## 3. Architecture

```
SiftBar/
├── PLAN.md
├── Package.swift
├── Sources/SiftBar/
│   ├── App/
│   │   ├── SiftBarApp.swift          # @main + MenuBarExtra + AppDelegate
│   │   ├── AppState.swift            # observable scan state
│   │   └── DashboardWindowController.swift
│   ├── Core/
│   │   ├── Models.swift              # Risk, ItemCategory, ItemAction, ScanItem
│   │   ├── CommandRunner.swift       # safe execution (no shell, with timeout)
│   │   ├── ScanCoordinator.swift     # parallel collectors + ordering
│   │   ├── ProcessSafety.swift       # protected process rules
│   │   ├── ReviewFilter.swift        # category/risk/search filters
│   │   ├── SystemProbe.swift         # memory and disk probes
│   │   ├── HistoryStore.swift        # audit log in Application Support
│   │   ├── CleanupWhitelist.swift    # allowed Trash roots
│   │   ├── RunningProcesses.swift    # app-in-use detection
│   │   └── ActionExecutor.swift      # previews and confirmed actions
│   ├── Collectors/
│   │   ├── MemoryCollector.swift
│   │   ├── ProcessCollector.swift
│   │   ├── StartupCollector.swift    # launch agents/daemons
│   │   ├── BrewCollector.swift
│   │   ├── DiskCollector.swift
│   │   ├── LargeConsumersCollector.swift
│   │   ├── CacheCollector.swift
│   │   └── OrphanCollector.swift
│   ├── UI/
│   │   ├── DashboardView.swift       # sidebar, stats, review list
│   │   ├── ItemRow.swift             # checkbox, risk, evidence, Finder reveal
│   │   ├── MenuContentView.swift     # menu bar popover
│   │   ├── ReviewFilterModel.swift
│   │   ├── ReviewActionModel.swift   # selection, confirmation, execution
│   │   └── ActionConfirmationView.swift
│   └── Support/
│       └── PathSizer.swift
├── Resources/
│   └── Info.plist                    # LSUIElement = true
├── Tests/SiftBarTests/               # 194 XCTest cases
└── scripts/
    ├── build.sh                      # direct swiftc build + .app assembly + ad-hoc sign
    ├── run.sh                        # build + open
    ├── clean.sh
    └── package.sh                    # APFS DMG with an /Applications symlink
```

### Technical decisions

| Decision | Choice | Reason |
|---|---|---|
| UI | SwiftUI (`MenuBarExtra`, macOS 13+) | Native, no Xcode required, lightweight |
| Window | `NSWindow` + `NSHostingView` opened from the menu | Avoids a window at launch; better for long lists than a popover |
| Concurrency | `async/await` + `TaskGroup` | Collectors run in parallel, UI stays responsive |
| Command execution | `Process` with an executable and an argument array | No shell, no argument injection |
| Timeout | 10 s per collector / 30 s per action | The app must not hang |
| Persistence | JSON history in `~/Library/Application Support/SiftBar/history.json` | Simple and auditable |
| Logging | Not implemented yet | Planned with history |
| Distribution | Ad-hoc signed DMG via GitHub Releases | No paid developer account yet |

---

## 4. Data model

```swift
enum Risk: String, Codable { case safe, caution, dangerous }

enum ItemCategory: String, Codable {
    case memory, processes, startup, services, disk, caches, leftovers
}

enum ItemAction: Equatable {
    case none                               // informational only
    case killProcess(pid: Int32, name: String)
    case removeLoginItem(name: String)      // declared, not collected yet
    case disableLaunchItem(label: String)
    case enableLaunchItem(label: String)
    case stopService(name: String)
    case deletePath(path: String, bytes: Int64)
}

struct ScanItem: Identifiable {
    let id: UUID
    let category: ItemCategory
    let title: String
    let detail: String
    let impactLabel: String        // "1.7 GB", "39 processes", "4.1 GB swap"
    let impactBytes: Int64?        // used for ordering
    let risk: Risk
    let action: ItemAction
    let evidence: String           // command or path that produced the item
    let children: [ScanItem]       // per-PID rows for grouped processes
}
```

`ScanItem.canBeChanged` is true only for actionable items that are not
`Dangerous` and do not require administrator rights.

---

## 5. Collectors (Phase 1)

| Collector | Source | Output |
|---|---|---|
| Memory | `vm_stat`, `sysctl vm.swapusage`, `memory_pressure` | pressure, swap used, pages |
| Processes | `ps -Ao pid=,user=,rss=,comm=` | processes above 150 MB, grouped by executable, top 12 |
| Startup | `launchctl list`, `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `launchctl print-disabled` | failing labels and third-party launch items; disabled labels appear as disabled with an enable action |
| Services | `brew services list` | started, errored, or scheduled services |
| Disk | `df -k` | free/used space and usage risk |
| Caches | Fixed whitelist (npm, Expo, Xcode DerivedData, Gradle, Homebrew, CoreSimulator, general caches) | size per cache above 20 MB; warns when a related app is running |
| Big consumers | `du -k -d 1` on Downloads, Desktop, Documents, Movies, Pictures, Music | files and folders above 1 GB, read-only |
| Leftovers | Installed apps vs. `~/Library/Application Support` | folders with no matching app above 200 MB, top 10 |

**Robustness rules:** each collector runs independently; one failure does not
break the scan; denied permissions become an informational item.

Login items (`osascript` / System Events) are deferred because ad-hoc builds
trigger a TCC prompt on every launch.

---

## 6. Risk analysis (Phase 2)

| Situation | Risk | Suggested action |
|---|---|---|
| Recreatable cache (npm, Expo, Gradle, Homebrew) | Safe | Move to Trash |
| User launch agent | Safe | Disable |
| System-wide launch agent/daemon (`/Library`) | Caution | Locked: requires admin |
| Launch item that keeps failing | Caution | Disable |
| Homebrew service that starts at login | Safe | Stop |
| Heavy app process (≥ 1 GB RSS) | Caution | Quit (warning) |
| Protected process, root process, or system binary | Dangerous | Never |
| SIP-protected path | Dangerous | Never (blocked) |
| Application Support folder with no matching app | Caution | Review; read-only for now |
| Large file/folder (≥ 1 GB) | Caution | Review in Finder; read-only |
| Disk ≥ 80% used | Caution | Review |
| Disk ≥ 90% used | Dangerous | Review |

Each item also carries an **impact score** for ordering: bytes freed > memory >
process count.

---

## 7. Safe execution (Phase 3)

1. The user selects changeable items (checkbox) and clicks the action button.
2. The confirmation sheet lists every selected item with its **exact command**
   and risk.
3. Confirmation: `Safe` and `Caution` require the explicit action button;
   `Dangerous`, admin-only, and read-only items have no checkbox.
4. Actions run sequentially with a timeout; each result is reported.
5. The app rescans, shows a result card with reclaimed bytes and failures, and
   appends the batch to the audit history.

**Implemented actions:**

| Action | Command / behavior |
|---|---|
| Quit process | `/bin/kill -TERM <pid>`; grouped rows expand into per-PID rows |
| Disable launch item | `launchctl bootout gui/<uid>/<label>` then `launchctl disable gui/<uid>/<label>` |
| Enable launch item | `launchctl enable gui/<uid>/<label>` then `launchctl bootstrap gui/<uid> <plist>` |
| Stop Homebrew service | `brew services stop <name>` |
| Remove cache | Move the folder to the Trash (reversible); only whitelisted cache roots are accepted |

**Required guardrails:**

- Never kill PID 1, `WindowServer`, `loginwindow`, `launchd`, root processes,
  or processes running from system paths.
- Never offer actions on `Dangerous` items.
- Lock `/Library` launch items because they require admin rights.
- Do not run `sudo` in v1; system-level actions are deferred to Phase 5.
- The executor re-checks the cleanup whitelist (including path traversal and
  symlink escapes) even though the collectors already produce known paths.
- System-wide caches under `/Library` are locked because they require admin
  rights; they are shown but never actioned.
- No shell interpolation: every command uses an executable plus an argument
  array.
- Confirm before every batch; no automatic cleanup.
- Append every batch to `~/Library/Application Support/SiftBar/history.json`
  so actions remain auditable.

---

## 8. Phases and acceptance criteria

Each phase ends at an **approval gate**: the work is delivered, you test it, and
only then do we move on.

### Phase 0 — Skeleton (≈ 30–60 min) ✅
- [x] `Package.swift`, folder structure, `Info.plist`
- [x] Menu bar app opens, shows Analyze, and opens an empty window
- [x] `scripts/build.sh` produces an ad-hoc signed `SiftBar.app`
- **Acceptance:** menu bar icon, app opens and closes without errors. ✅

### Phase 1 — Read-only collection (≈ 1–2 h) ✅
- [x] All seven collectors + `ScanReport`
- [x] Dashboard with counters; working Analyze button
- [x] No actions available yet
- **Acceptance:** numbers match `top`/`df`; a full scan finishes in under a
  second. ✅

### Phase 2 — Classification and review (≈ 1–2 h) ✅
- [x] Risk rules, risk badges, ordering by impact
- [x] Filters by category/risk; search across title, detail, evidence, category
- [x] `Dangerous` items are informational only
- [x] Protected system processes (`PID 1`, `WindowServer`, `launchd`, root,
  system binaries) become `Dangerous` and never receive a kill action
- [x] Processes sharing an executable are grouped
- [x] `/Library` launch items become `Caution` (admin required); user items stay
  `Safe`
- **Acceptance:** the list is understandable without reading the code; risks
  match §6. ✅

### Phase 3 — Safe actions (≈ 1–2 h) ✅
- [x] Quit single-PID processes with `kill -TERM`
- [x] Expand grouped process rows and quit individual PIDs
- [x] Disable user launch agents with `launchctl bootout` + `disable`
- [x] Enable disabled launch agents again with `launchctl enable` +
  `bootstrap`
- [x] Stop Homebrew services with `brew services stop`
- [x] Move cache folders to the Trash
- [x] Command preview, confirmation sheet, per-item results, rescan, and result
  card
- [ ] Remove login items via System Events (deferred: TCC prompt on every
  ad-hoc build)
- **Acceptance:** tested on real reversible items; no protected process or
  admin-only item can be actioned. ✅

### Phase 4 — Cache and disk cleanup (≈ 1–2 h) ✅
- [x] Cache size calculation and fixed whitelist
- [x] Trash-based removal with confirmation and reclaimed-bytes report
- [x] Disk cleanup: largest files/folders (`du -d 1`) and biggest-consumers rows
- [x] Enforce the path whitelist inside `ActionExecutor` (traversal and symlink
  escapes included)
- [x] Warn when an app is running before removing its data
- **Acceptance:** test caches are removed; no path outside the whitelist is
  touched. ✅

### Phase 5 — Administrator privileges (≈ 2–4 h, optional) ⏸
- [ ] Privileged helper (`SMAppService`) for system-level actions
- [ ] Authorization dialog; audited commands
- **Blocked:** `SMAppService` requires a Developer ID/team and a notarized
  helper. Current behavior correctly locks `/Library` items instead.
- **Acceptance:** a system action works with authorization and fails cleanly
  when denied.

### Phase 6 — History and polish (optional) ⏳
- [x] History/audit log: JSON in Application Support, plus a read-only History
  sheet
- [x] Keyboard shortcuts: `⌘R` Analyze, `⌘Y` History, `⌘F` Find; History item
  in the menu bar popover
- [ ] Full AppKit menu bar (SwiftUI `MenuBarExtra` owns the main menu)
- [ ] Keyboard selection/navigation in the review list
- [ ] Notifications for scan completion (only when appropriate)
- [ ] Scheduling with `launchd`
- [ ] Custom app icon; "monitor only" mode
- [ ] Markdown report export

### Phase 7 — Distribution ✅
- [x] APFS DMG with an `/Applications` symlink (`scripts/package.sh`)
- [x] GitHub Release published automatically from `v*` tags
- [x] README download link to the latest DMG
- [ ] Notarization (blocked on a Developer ID)

---

## 9. Testing

- **Unit tests:** parsers for `vm_stat`, `ps`, `launchctl`, `brew services`,
  `du`; risk rules; review filters; process safety; action previews and
  selection; grouped-process children; disabled/enabled launch labels; history
  storage; cleanup whitelist enforcement; largest-consumer ranking; running-app
  warnings.
- **Integration tests:** each collector against real data; `CommandRunner` with
  timeouts and invalid arguments; a full scan.
- **Safety tests:** protected PIDs, admin-only items, read-only items, path and
  command construction, traversal and symlink escapes.
- **Manual tests:** compare numbers with Activity Monitor, `top`, `df`, and
  `launchctl list`; verify Finder reveal and confirmation flows.
- **Current suite:** 194 XCTest cases. CI runs `swift build`,
  `swift build -c release`, `swift test --parallel`, and validates the app and
  DMG.
- **Gaps:** no automated UI tests; destructive actions are not executed in
  tests; privileged actions are deferred.

---

## 10. Risks and mitigation

| Risk | Mitigation |
|---|---|
| Local CLT cannot link the SwiftPM manifest | Scripts build with `swiftc`; CI covers `swift build`/`swift test` |
| TCC blocks reading `~/Library` | Detect and show a warning; link to Settings |
| Killing a process with unsaved work | `Caution` risk, app name, explicit confirmation |
| Deleting a cache in use | Warn when a related app is running and `Caution` risk |
| Numbers differ from Finder | Explain category vs. folder (the "15 GB in Documents" lesson) |
| Ad-hoc signing triggers Gatekeeper | Document right-click → Open; notarize when a Developer ID exists |
| Privileged helper is not shippable without signing | Defer Phase 5 until Developer ID + notarization |
| Full AppKit menu bar is unavailable | SwiftUI `MenuBarExtra` owns the main menu; shortcuts and the popover cover the commands |
| History is append-only | A corrupted file is ignored; there is no UI to clear it yet |
| App becomes heavy | Timeouts, parallel collectors, on-demand UI |

---

## 11. Next step

Recommended order:

1. Add keyboard selection/navigation in the review list.
2. Add notifications, scheduling, and a custom icon.
3. Add login item removal when TCC behavior is acceptable.
4. Add Markdown report export and a "monitor only" mode.
5. Leave the privileged helper (Phase 5) and notarization until a Developer ID
   is available.

> "SiftBar" is still a provisional name. If it changes, the folder, target,
> bundle ID, and release names change with it.
