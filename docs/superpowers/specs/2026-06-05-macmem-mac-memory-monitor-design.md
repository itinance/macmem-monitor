# macmem — macOS Memory Monitor (CLI + MenuBar)

**Date:** 2026-06-05
**Status:** Approved design — ready for implementation planning
**License:** MIT

## 1. Purpose

A macOS tool that gives an honest, at-a-glance picture of system memory usage:

1. **Top 10 memory-heaviest apps**, with helper/renderer processes (e.g. "Brave Renderer", "Code Helper") collapsed into their parent app and summed.
2. **Swap usage** — accurate system-wide total, plus a ranked, confidence-labeled list of the apps most likely contributing to swap.
3. **Top 10 heaviest browser tabs** with their URLs, across Safari and Chromium browsers (Brave/Chrome/Edge), with per-tab memory as a best-effort estimate.

It ships as two front-ends over one shared engine: a **CLI** and a **MenuBar app**.

## 2. Scope & honest constraints

macOS does not cleanly expose two things this tool wants, so both are explicitly handled as **estimates with confidence**, never presented as measured truth:

- **Per-tab memory:** the browser knows which renderer process serves which tab, but does not expose that mapping. We read tab URLs via AppleScript and read renderer process memory via `libproc`, then **heuristically map** renderers→tabs by window/process ordering. Ambiguous mappings are left blank rather than guessed, and every estimate carries a confidence marker.
- **Per-process swap:** macOS exposes total swap (`sysctl vm.swapusage`) but not per-process swap bytes. We report the accurate total plus a **heuristic ranking of likely culprits** from `libproc` signals (page-ins, footprint-vs-resident delta, compressed memory), labeled as estimates.

A `MemoryProvider` protocol abstracts the data source. The default is the **native** implementation (approach A). A **shell-out** implementation (approach B: `ps`/`top`/`vm_stat`) can be added behind the same protocol later if native APIs prove insufficient — without touching the rest of the system.

### Out of scope (v1)
- Browsers other than Safari/Brave/Chrome/Edge (notably Firefox, which doesn't expose tabs via AppleScript).
- Historical/time-series tracking and charts.
- A browser extension for exact per-tab memory (considered and deferred).

## 3. Privileges & permissions

- **Per-process memory** via `proc_pid_rusage` reads processes owned by the **current user** without root — this covers Brave/Chrome/Claude/etc. Root-owned system processes require elevation.
  - **CLI:** runs as the invoking user. When non-root *and* unreadable processes are detected, it prints to stderr: `N processes not readable — run \`sudo macmem\` for full coverage.` sudo is never required, only suggested.
  - **MenuBar:** runs at user level by default. An **"Enable full access"** action installs a **privileged XPC helper** on demand via `SMAppService` (the GUI "sudo-equivalent"), enabling reads of root-owned processes.
- **Browser tab reading** triggers a one-time macOS **Automation (TCC)** prompt. If denied, the tabs section returns a `permissionNeeded` status; the rest of the snapshot is unaffected. The MenuBar app shows a **"Grant Automation"** banner that deep-links to System Settings.

## 4. Architecture

One SwiftPM mono-repo. A shared, UI-free engine (`MacMemCore`) computes an immutable `MemorySnapshot` that both front-ends render. Pure data in, pure data out.

### 4.1 Repo layout
```
macmem/
├── LICENSE                      # MIT
├── README.md
├── Package.swift                # MacMemCore (lib) + macmem (CLI executable)
├── Sources/
│   ├── MacMemCore/              # shared engine, no UI
│   └── macmem/                  # CLI — swift-argument-parser
├── Tests/MacMemCoreTests/
├── MenuBar/                     # Xcode project, depends on local MacMemCore package
│   └── MacMemMenuBar.xcodeproj
└── .github/workflows/           # CI: build + test (+ notarize when credentials present)
```
CLI and MenuBar are sibling directories/targets in one branch (not git branches) so the shared `Core` stays in sync. The MenuBar app is an Xcode project (rather than pure SwiftPM) because building and signing a `.app` bundle is far smoother in Xcode; it consumes `MacMemCore` as a local package dependency.

### 4.2 `MacMemCore`

**Data source (behind a protocol):**
- `MemoryProvider` (protocol) — the seam between the engine and the OS.
- `NativeMemoryProvider` (default, approach A): `proc_listpids` + `proc_pid_rusage` → `ri_phys_footprint` for per-process memory; `sysctl vm.swapusage` for swap. `phys_footprint` is chosen deliberately because it matches Activity Monitor's "Memory" column, so totals feel correct to users.
- `ShellMemoryProvider` (future, approach B): same protocol, parses `ps`/`top`/`vm_stat`.

**Domain models (value types):**
- `ProcessSample` — pid, ppid, responsiblePid, bundleID, name, footprintBytes, residentBytes, pageIns, isReadable.
- `AppGroup` — display name, bundleID, totalFootprintBytes, processCount, member pids.
- `SwapInfo` — totalBytes, usedBytes, freeBytes, swapIns, swapOuts.
- `SwapCulprit` — appGroup ref, score, confidence.
- `BrowserTab` — browser, title, url, estimatedBytes?, confidence.
- `MemorySnapshot` — top apps, `SwapInfo` + culprits, top tabs, plus **per-section status** (ok / partial / permissionNeeded) and counts of unreadable processes.

**Engine components:**
- `AppGrouper` — collapses helper/renderer processes into their parent app via **responsible-PID + bundle identifier**, sums footprints, returns top-N `AppGroup`s.
- `SwapEstimator` — accurate total from `vm.swapusage`; ranks likely culprits from `libproc` signals; assigns confidence.
- `BrowserInspector` — AppleScript bridge per supported browser (Safari + Chromium) for tab URLs/titles; heuristic renderer↔tab mapping with confidence; returns top-N tabs.
- `SnapshotBuilder` — orchestrates provider + grouper + estimator + inspector into one `MemorySnapshot`. Each section is computed **independently**: a failure in one yields a partial snapshot with that section's status set, never a crash.

### 4.3 Data flow
```
NativeMemoryProvider ─┐
                      ├─→ SnapshotBuilder ─→ MemorySnapshot ─┬─→ CLI renderer (table / JSON)
BrowserInspector ─────┘                                     └─→ MenuBar UI (SwiftUI)
```

## 5. CLI (`macmem`)

- Built on **swift-argument-parser**. Default invocation prints the full snapshot: top-10 apps table, swap summary + culprits, top-10 browser tabs.
- **Flags:** `--json`, `--watch [interval]` (default 2s), `--top N` (default 10), `--no-tabs`, `--no-swap`, `--browser <name>`.
- Estimated values are visually marked (`~` prefix / "est." column + confidence) so a heuristic is never mistaken for a measurement.
- Privilege hint to stderr when applicable (see §3). Meaningful exit codes (0 ok; non-zero on fatal provider failure).

## 6. MenuBar app

- **SwiftUI `MenuBarExtra`**, minimum target **macOS 13 (Ventura)+**.
- Status item shows a compact metric (memory used %). Clicking opens a panel with three sections — top apps, swap, browser tabs — mirroring the CLI data.
- Polls `SnapshotBuilder` on a background timer (**default 5s**, configurable); results published to the UI on the main actor.
- Two permission banners: **"Grant Automation"** (deep-links to System Settings) for tabs; **"Enable full access"** (installs privileged XPC helper via `SMAppService`) for root processes.
- Preferences: refresh interval, **launch at login** (`SMAppService`), top-N.

## 7. Distribution

- **CLI** → Homebrew **formula** in a custom tap; builds from source via `swift build`. No Apple Developer account required.
- **MenuBar** → Homebrew **Cask** installing the `.app` into `/Applications`. CI **code-signs + notarizes** with a Developer ID when credentials are present; otherwise produces an unsigned build with documented Gatekeeper-bypass steps. The repo is structured so notarization is a drop-in CI step whenever an Apple Developer account ($99/yr) is available.
- Releases via GitHub Releases feeding the tap.

## 8. Testing

- `MacMemCore` unit tests inject **fake `ProcessSample` lists through the `MemoryProvider` protocol**, so `AppGrouper`, `SwapEstimator`, and formatters are tested deterministically with no dependence on the live system.
- `NativeMemoryProvider` has a CI smoke test that reads the test process itself.
- `BrowserInspector` AppleScript parsing is tested against **recorded fixtures**; live browser tests are skipped on CI (no browsers / no Automation grant).
- CLI **golden tests** assert table and JSON output from a fixed snapshot.

## 9. Error handling

- Provider and inspector errors are typed Swift errors.
- The snapshot is **resilient by construction**: apps / swap / tabs are independent sections, each carrying its own status (`ok` / `partial` / `permissionNeeded` / `error`). Front-ends render whatever succeeded and surface the rest as inline status, never failing the whole run.

## 10. Success criteria

- `macmem` prints the three sections with numbers that match Activity Monitor's "Memory" column for the current user's apps.
- Helper/renderer processes are correctly grouped under their parent app (verified against Brave and Claude Code).
- Total swap matches `sysctl vm.swapusage`; culprit ranking is plausible and clearly marked as estimates.
- Browser tabs list URLs for supported browsers; per-tab memory shows estimates with confidence and blanks where ambiguous.
- MenuBar app refreshes live and offers both permission paths.
- Both front-ends installable via Homebrew.
