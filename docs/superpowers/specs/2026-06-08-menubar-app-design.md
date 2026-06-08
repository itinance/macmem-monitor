# macmem MenuBar App (Plan 2) — Design

**Status:** Approved 2026-06-08.
**Goal:** A native macOS menubar app that surfaces the same honest memory data as the `macmem` CLI, plus a small set of interactive actions, by reusing the existing `MacMemCore` engine.

## Summary

A SwiftUI `MenuBarExtra` app (macOS 13+) lives beside the existing CLI in the same SwiftPM package. The collapsed menubar item shows an icon tinted by **real OS memory pressure**. Opening the dropdown shows the three familiar sections (top apps, swap + compressed memory, browser tabs) and offers four actions: quit an app, reveal in Activity Monitor, run `purge`, and copy/open. The app runs unprivileged, requires nothing persistent, and degrades honestly everywhere — consistent with the project's honesty principle ("every displayed number is measured; ambiguous values are labelled or left blank, never faked").

## Decisions (from brainstorming)

- **Role:** monitor **and** actions — a control surface, not just a display.
- **Collapsed bar:** icon **+ live memory pressure** (green / yellow / red).
- **Actions:** quit an app, reveal in Activity Monitor, run `purge`, copy snapshot / open CLI. The two destructive/privileged ones (quit, purge) confirm first.
- **Refresh:** **adaptive** — cheap pressure polling (~5s) while collapsed; full snapshot (~2.5s) only while the dropdown is open.
- **Privilege:** **no persistent root helper.** `purge` uses a one-shot native admin prompt; full process coverage is unprivileged and degrades honestly; quit is limited to the current user's apps. (The SMAppService privileged-helper path was considered and rejected because it would mandate code-signing/notarization up front.)
- **Build/packaging:** SwiftPM executable target + a `just app` script that assembles the `.app` bundle (`LSUIElement` Info.plist) and ad-hoc codesigns locally. No Xcode project; XCTest stays the test runner.
- **Architecture:** thin SwiftUI views over an `@Observable` view model, a UI-free snapshot engine, and a `SystemActions` protocol seam — mirroring the CLI's `MemoryProvider`/`TabSource` seam discipline.

## File Structure

```
Package.swift                        # + executableTarget "MacMemMenuBar", + MacMemMenuBarTests
Sources/
  MacMemCore/
    MemoryPressure.swift     (new)   # MemoryPressure enum + reading
    MemoryProvider.swift     (edit)  # protocol gains pressure(); Fake gains settable value
    NativeMemoryProvider.swift(edit) # pressure() via kern.memorystatus_vm_pressure_level
  macmem/                            # CLI — untouched
  MacMemMenuBar/             (new)
    MacMemMenuBarApp.swift           # @main App, MenuBarExtra scene
    MenuViewModel.swift              # @Observable single source of truth
    SnapshotEngine.swift             # adaptive timers; collapsed=pressure, open=full snapshot
    SystemActions.swift              # protocol seam + FakeSystemActions
    LiveSystemActions.swift          # real impl (NSRunningApplication, AppleScript purge, open -a, pasteboard)
    Views/
      MenuContentView.swift          # dropdown layout
      SectionViews.swift             # TopApps / Swap / Tabs row views
      PermissionBanner.swift         # Automation-denied / unreadable-count banners
      BarLabel.swift                 # collapsed icon + pressure tint
Tests/
  MacMemMenuBarTests/                # ViewModel + engine + actions, all with fakes
justfile                     (edit)  # + `just app`, `just run-app`
```

## Core Addition: Memory Pressure

The only genuinely new engine capability.

```swift
public enum MemoryPressure: String, Sendable, Codable {
    case normal, warn, critical, unknown
}
```

- Read via `sysctlbyname("kern.memorystatus_vm_pressure_level", ...)`: `1 → .normal`, `2 → .warn`, `4 → .critical`, anything else → `.unknown`.
- Added to `MemoryProvider` as `func pressure() -> MemoryPressure` — **non-throwing**; returns `.unknown` on any failure (honest, never a fake green).
- `NativeMemoryProvider` implements the sysctl read. `FakeMemoryProvider` gains a settable stored `pressure` value (default `.normal`) for tests.

## Components & Data Flow

**`SnapshotEngine`** (no UI) owns the adaptive cadence:
- *Collapsed:* ~5s timer calling only `provider.pressure()` (one cheap sysctl).
- *Open:* ~2.5s timer calling `SnapshotBuilder.build(...)` for a full `MemorySnapshot`; stops when the menu closes.
- `setMenuOpen(Bool)` switches modes. Sampling runs off the main thread; results are delivered to the view model on the main actor.

**`MenuViewModel`** (`@Observable`) is the single source the views read:
- Holds `pressure`, latest `MemorySnapshot`, derived per-section status, `isMenuOpen`, and a "last updated" timestamp.
- Forwards intents (`quit(app:)`, `purge()`, `reveal(app:)`, `copySnapshot()`) to `SystemActions`.
- Constructed with injected `provider`, `tabSource`, `actions` — tests use all fakes, zero system calls.

**Flow:** the `MenuBarExtra` label binds to `viewModel.pressure` (glyph + tint). Opening the dropdown sets `isMenuOpen = true` → engine switches to full-snapshot mode → snapshot flows back → `MenuContentView` renders the three sections. Closing reverses it.

## Actions & Privilege

```swift
protocol SystemActions {
    func quit(app: AppGroup) async -> ActionResult       // graceful terminate
    func purge() async -> ActionResult                   // one-shot admin prompt
    func revealInActivityMonitor(app: AppGroup)
    func copySnapshot(_ text: String)
}
enum ActionResult: Equatable { case ok, cancelled, failed(String), notPermitted }
```

- **Quit an app:** map `AppGroup` → `NSRunningApplication` (bundle id, else pid) and call `.terminate()` (graceful). Only the current user's apps are targetable; root/other-user groups show the control disabled with a tooltip. **Confirmation required**, naming the app and its measured footprint.
- **Run purge:** `NSAppleScript("do shell script \"/usr/sbin/purge\" with administrator privileges")`. macOS shows its native admin sheet each time; cancel → `.cancelled` (silent). No stored credentials, nothing persistent. **Confirmation first**, with an honest one-line note (flushes caches, brief disk-I/O spike).
- **Reveal in Activity Monitor:** `open -a "Activity Monitor"` plus a short hint (no per-pid deep link exists; we are honest about that rather than faking a jump).
- **Copy:** render the current snapshot via the existing `TextRenderer` and write to `NSPasteboard` — what you copy is exactly what `macmem` prints.

Privilege summary: nothing persistent, nothing required. Purge is the only elevated action and prompts per use; everything else is unprivileged.

## Error & Permission Handling

Each section keeps `MacMemCore`'s `SectionStatus`, so the dropdown renders status per section, never all-or-nothing.

- **Automation (TCC) for tabs:** `tabsStatus == .permissionNeeded` → a `PermissionBanner` in the tabs section with a button deep-linking to System Settings → Privacy & Security → Automation (`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`). Never fabricate tab data when denied. `.partial` → show what succeeded plus a quiet "some browsers failed" note.
- **Unreadable processes:** `unreadableProcessCount > 0` → honest footer "N processes not shown (owned by other users)". Never silently omitted.
- **Compressed memory unavailable:** `compressedAvailable == false` → swap section states "per-app compressed memory unavailable (could not read from top)" — same wording as the CLI.
- **Pressure unknown:** `pressure == .unknown` → neutral un-tinted icon (never fake green), tooltip "memory pressure unavailable".
- **Action results:** `.failed(msg)` → transient inline message; `.cancelled` → silent; `.notPermitted` → control stays disabled.
- **No infinite spinners:** if a refresh throws, the prior snapshot stays visible with a subtle "stale" timestamp rather than blanking.

## Testing

GUI rendering is intentionally untested (logic lives in the view model, not the views). Coverage:

- **`MemoryPressure`:** sysctl-value → enum mapping for `1/2/4/other` (pure function, table-driven).
- **`FakeMemoryProvider.pressure`:** returns the configured value.
- **`SnapshotEngine`:** a spy provider counts `pressure()` vs `listProcesses()` calls; assert collapsed mode calls only `pressure()`, open mode triggers a full build, and closing stops full sampling.
- **`MenuViewModel`:** with all fakes — snapshot flows into published state; per-section status is derived correctly; each intent forwards to `SystemActions` exactly once with the right argument; stale-on-error keeps the prior snapshot.
- **`SystemActions` seam:** `FakeSystemActions` records calls and returns a scripted `ActionResult`; the view model surfaces `.failed`/`.cancelled`/`.notPermitted` correctly. `LiveSystemActions` side effects are not unit-tested (real terminate/purge), but any pure mapping (e.g. `AppGroup` → target resolution) is factored out and tested.

Target: every non-GUI unit covered; existing 97 `MacMemCore`/CLI tests stay green.

## Out of Scope (YAGNI)

- Persistent privileged helper / SMAppService daemon.
- Per-tab memory (no API exposes it — same as the CLI).
- Always-on background sampling while collapsed.
- Launch-at-login (can be a later, separate increment).
- Code-signing/notarization for distribution (later milestone; local ad-hoc signing for now).
- Charts/history/graphs.
```
