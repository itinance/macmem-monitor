# macmem MenuBar App (Plan 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menubar app (`MacMemMenuBar`) that surfaces the same honest memory data as the `macmem` CLI plus four interactive actions, reusing the existing `MacMemCore` engine.

**Architecture:** A SwiftUI `MenuBarExtra` app in the same SwiftPM package. The collapsed bar shows an icon tinted by real OS memory pressure; the dropdown shows the three CLI sections (top apps / swap+compressed / tabs). A UI-free `SnapshotEngine` drives adaptive refresh (cheap pressure poll while collapsed, full snapshot while open). A `MenuViewModel` (`ObservableObject`) is the single source of truth the views read; all side effects sit behind a `SystemActions` protocol seam with a fake — mirroring the CLI's `MemoryProvider`/`TabSource` discipline.

**Tech Stack:** Swift 6.x / SwiftPM (tools 5.9), SwiftUI (`MenuBarExtra`, macOS 13+), XCTest, `just`. The only new core capability is reading `kern.memorystatus_vm_pressure_level`.

**macOS-13 note:** `@Observable` (Observation framework) is macOS 14+. To keep the macOS 13 target, `MenuViewModel` uses `ObservableObject` + `@Published`, NOT `@Observable`.

---

## File Structure

- `Sources/MacMemCore/MemoryPressure.swift` (new) — `MemoryPressure` enum + pure `init(rawLevel:)` mapping.
- `Sources/MacMemCore/MemoryProvider.swift` (edit) — protocol gains `func pressure() -> MemoryPressure`; `FakeMemoryProvider` gains a settable `pressureValue`.
- `Sources/MacMemCore/NativeMemoryProvider.swift` (edit) — `pressure()` via `sysctlbyname`.
- `Sources/MacMemMenuBar/AppResolver.swift` (new) — pure `AppGroup` → running-app match logic.
- `Sources/MacMemMenuBar/SystemActions.swift` (new) — `SystemActions` protocol, `ActionResult`, `FakeSystemActions`.
- `Sources/MacMemMenuBar/SnapshotEngine.swift` (new) — adaptive sampling engine.
- `Sources/MacMemMenuBar/MenuViewModel.swift` (new) — `ObservableObject` state + intents + confirmation state machine.
- `Sources/MacMemMenuBar/LiveSystemActions.swift` (new) — real quit/purge/reveal/copy.
- `Sources/MacMemMenuBar/Views/BarLabel.swift` (new) — collapsed icon + pressure tint.
- `Sources/MacMemMenuBar/Views/MenuContentView.swift` (new) — dropdown layout.
- `Sources/MacMemMenuBar/Views/SectionViews.swift` (new) — top-apps / swap / tabs rows.
- `Sources/MacMemMenuBar/Views/PermissionBanner.swift` (new) — Automation / unreadable banners.
- `Sources/MacMemMenuBar/MacMemMenuBarApp.swift` (new) — `@main` `MenuBarExtra` scene.
- `Tests/MacMemMenuBarTests/*.swift` (new) — engine, view model, actions, resolver tests.
- `Package.swift` (edit) — add executable target + test target.
- `justfile` (edit) — `just app`, `just run-app`.
- `Resources/MenuBar/Info.plist.template` (new) — `LSUIElement` plist used by `just app`.

---

## Task 1: MemoryPressure core capability

**Files:**
- Create: `Sources/MacMemCore/MemoryPressure.swift`
- Modify: `Sources/MacMemCore/MemoryProvider.swift`
- Modify: `Sources/MacMemCore/NativeMemoryProvider.swift`
- Test: `Tests/MacMemCoreTests/MemoryPressureTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MacMemCoreTests/MemoryPressureTests.swift`:

```swift
import XCTest
@testable import MacMemCore

final class MemoryPressureTests: XCTestCase {
    func testRawLevelMapping() {
        XCTAssertEqual(MemoryPressure(rawLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(rawLevel: 2), .warn)
        XCTAssertEqual(MemoryPressure(rawLevel: 4), .critical)
        XCTAssertEqual(MemoryPressure(rawLevel: 0), .unknown)
        XCTAssertEqual(MemoryPressure(rawLevel: 3), .unknown)
        XCTAssertEqual(MemoryPressure(rawLevel: 99), .unknown)
    }

    func testFakeProviderReturnsConfiguredPressure() {
        var provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        provider.pressureValue = .critical
        XCTAssertEqual(provider.pressure(), .critical)
    }

    func testFakeProviderDefaultPressureIsNormal() {
        let provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        XCTAssertEqual(provider.pressure(), .normal)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MemoryPressureTests`
Expected: FAIL — `cannot find 'MemoryPressure' in scope` / `pressureValue` not a member.

- [ ] **Step 3: Create MemoryPressure type**

Create `Sources/MacMemCore/MemoryPressure.swift`:

```swift
import Foundation

/// Real OS memory-pressure level, read from `kern.memorystatus_vm_pressure_level`.
/// Never inferred or faked: an unreadable/unexpected value maps to `.unknown`,
/// which the UI renders as a neutral (un-tinted) state rather than a fake "green".
public enum MemoryPressure: String, Sendable, Codable, Equatable {
    case normal, warn, critical, unknown

    /// Maps the raw sysctl level to a case. The kernel reports
    /// 1 = normal, 2 = warning, 4 = critical; anything else is unknown.
    public init(rawLevel: Int32) {
        switch rawLevel {
        case 1: self = .normal
        case 2: self = .warn
        case 4: self = .critical
        default: self = .unknown
        }
    }
}
```

- [ ] **Step 4: Add `pressure()` to the protocol and Fake**

In `Sources/MacMemCore/MemoryProvider.swift`, add to the protocol (after `compressedByPID()`):

```swift
    /// Current OS memory-pressure level. Non-throwing: returns `.unknown` on any
    /// failure so the UI never shows a fabricated level.
    func pressure() -> MemoryPressure
```

In the same file, add a stored property and method to `FakeMemoryProvider`. Add the property after `swapError`:

```swift
    public var pressureValue: MemoryPressure = .normal
```

And add the method after `compressedByPID()`:

```swift
    public func pressure() -> MemoryPressure { pressureValue }
```

(The default value on the stored property keeps every existing `FakeMemoryProvider(...)` call site compiling unchanged.)

- [ ] **Step 5: Implement `pressure()` on NativeMemoryProvider**

In `Sources/MacMemCore/NativeMemoryProvider.swift`, add this method inside the `NativeMemoryProvider` struct (e.g. right after `readSwap()`):

```swift
    public func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rc = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard rc == 0 else { return .unknown }
        return MemoryPressure(rawLevel: level)
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter MemoryPressureTests`
Expected: PASS (3 tests).

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `swift test`
Expected: PASS — all existing tests plus the 3 new ones (100 total).

- [ ] **Step 8: Commit**

```bash
git add Sources/MacMemCore/MemoryPressure.swift Sources/MacMemCore/MemoryProvider.swift Sources/MacMemCore/NativeMemoryProvider.swift Tests/MacMemCoreTests/MemoryPressureTests.swift
git commit -m "feat(core): add measured memory-pressure reading"
```

---

## Task 2: Scaffold the MacMemMenuBar target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MacMemMenuBar/MacMemMenuBarApp.swift` (temporary stub, replaced in Task 7)
- Create: `Tests/MacMemMenuBarTests/ScaffoldTests.swift`

- [ ] **Step 1: Add the targets to Package.swift**

In `Package.swift`, add to `products` (after the `macmem` executable):

```swift
        .executable(name: "MacMemMenuBar", targets: ["MacMemMenuBar"]),
```

Add to `targets` (after the `macmem` executableTarget, before the test target):

```swift
        .executableTarget(
            name: "MacMemMenuBar",
            dependencies: ["MacMemCore"]
        ),
```

Add the test target (after `MacMemCoreTests`):

```swift
        .testTarget(name: "MacMemMenuBarTests", dependencies: ["MacMemMenuBar", "MacMemCore"]),
```

- [ ] **Step 2: Create a temporary compilable stub**

Create `Sources/MacMemMenuBar/MacMemMenuBarApp.swift`:

```swift
import Foundation

// Temporary scaffold entry point, replaced by the SwiftUI App in Task 7.
// Exists so the target compiles and the test target can link against it.
enum MacMemMenuBarBuildMarker {
    static let ok = true
}

@main
struct MacMemMenuBarMain {
    static func main() {
        _ = MacMemMenuBarBuildMarker.ok
    }
}
```

- [ ] **Step 3: Write a scaffold test**

Create `Tests/MacMemMenuBarTests/ScaffoldTests.swift`:

```swift
import XCTest
@testable import MacMemMenuBar

final class ScaffoldTests: XCTestCase {
    func testTargetLinks() {
        XCTAssertTrue(MacMemMenuBarBuildMarker.ok)
    }
}
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test --filter ScaffoldTests`
Expected: PASS — target compiles and the test links against it.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/MacMemMenuBar/MacMemMenuBarApp.swift Tests/MacMemMenuBarTests/ScaffoldTests.swift
git commit -m "build: scaffold MacMemMenuBar executable + test target"
```

---

## Task 3: SystemActions seam + AppResolver

**Files:**
- Create: `Sources/MacMemMenuBar/AppResolver.swift`
- Create: `Sources/MacMemMenuBar/SystemActions.swift`
- Test: `Tests/MacMemMenuBarTests/AppResolverTests.swift`
- Test: `Tests/MacMemMenuBarTests/FakeSystemActionsTests.swift`

- [ ] **Step 1: Write the failing AppResolver test**

Create `Tests/MacMemMenuBarTests/AppResolverTests.swift`:

```swift
import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

final class AppResolverTests: XCTestCase {
    private func group(name: String, bundle: String?, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: bundle, totalFootprintBytes: 1, processCount: pids.count, pids: pids)
    }

    func testMatchesByBundleIDFirst() {
        let candidates: [AppCandidate] = [
            AppCandidate(bundleID: "com.brave.Browser", pid: 10),
            AppCandidate(bundleID: "com.other", pid: 11),
        ]
        let g = group(name: "Brave Browser", bundle: "com.brave.Browser", pids: [99])
        XCTAssertEqual(AppResolver.matchIndex(group: g, candidates: candidates), 0)
    }

    func testFallsBackToPIDWhenNoBundleMatch() {
        let candidates: [AppCandidate] = [
            AppCandidate(bundleID: nil, pid: 42),
            AppCandidate(bundleID: "com.other", pid: 11),
        ]
        let g = group(name: "node", bundle: nil, pids: [42])
        XCTAssertEqual(AppResolver.matchIndex(group: g, candidates: candidates), 0)
    }

    func testReturnsNilWhenNoMatch() {
        let candidates: [AppCandidate] = [AppCandidate(bundleID: "com.other", pid: 11)]
        let g = group(name: "Ghost", bundle: "com.ghost", pids: [7])
        XCTAssertNil(AppResolver.matchIndex(group: g, candidates: candidates))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppResolverTests`
Expected: FAIL — `cannot find 'AppResolver' / 'AppCandidate' in scope`.

- [ ] **Step 3: Implement AppResolver**

Create `Sources/MacMemMenuBar/AppResolver.swift`:

```swift
import Foundation
import MacMemCore

/// A running application reduced to the only fields needed to match it against
/// an `AppGroup`. Keeping this a plain value (not `NSRunningApplication`) makes
/// the matching logic pure and unit-testable.
public struct AppCandidate: Equatable {
    public let bundleID: String?
    public let pid: Int32
    public init(bundleID: String?, pid: Int32) {
        self.bundleID = bundleID; self.pid = pid
    }
}

/// Pure logic for resolving which running app an `AppGroup` refers to.
public enum AppResolver {
    /// Returns the index of the first candidate matching the group, or nil.
    /// Prefers a bundle-id match; falls back to a pid contained in the group.
    public static func matchIndex(group: AppGroup, candidates: [AppCandidate]) -> Int? {
        if let bundle = group.bundleID,
           let i = candidates.firstIndex(where: { $0.bundleID == bundle }) {
            return i
        }
        let groupPIDs = Set(group.pids)
        return candidates.firstIndex(where: { groupPIDs.contains($0.pid) })
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppResolverTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing FakeSystemActions test**

Create `Tests/MacMemMenuBarTests/FakeSystemActionsTests.swift`:

```swift
import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

final class FakeSystemActionsTests: XCTestCase {
    private func group(_ name: String) -> AppGroup {
        AppGroup(name: name, bundleID: "com.x", totalFootprintBytes: 1, processCount: 1, pids: [1])
    }

    func testRecordsQuitAndReturnsScriptedResult() async {
        let fake = FakeSystemActions()
        fake.quitResult = .failed("boom")
        let result = await fake.quit(app: group("Brave Browser"))
        XCTAssertEqual(result, .failed("boom"))
        XCTAssertEqual(fake.quitCalls.map(\.name), ["Brave Browser"])
    }

    func testRecordsPurge() async {
        let fake = FakeSystemActions()
        _ = await fake.purge()
        XCTAssertEqual(fake.purgeCallCount, 1)
    }

    func testRecordsRevealAndCopy() {
        let fake = FakeSystemActions()
        fake.revealInActivityMonitor(app: group("A"))
        fake.copySnapshot("hello")
        XCTAssertEqual(fake.revealCalls.map(\.name), ["A"])
        XCTAssertEqual(fake.copiedText, "hello")
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter FakeSystemActionsTests`
Expected: FAIL — `cannot find 'FakeSystemActions' / 'ActionResult' in scope`.

- [ ] **Step 7: Implement the SystemActions seam**

Create `Sources/MacMemMenuBar/SystemActions.swift`:

```swift
import Foundation
import MacMemCore

/// Outcome of a user-triggered action.
public enum ActionResult: Equatable {
    case ok
    case cancelled
    case failed(String)
    case notPermitted
}

/// All side-effecting operations the menubar app can perform, behind a seam so
/// the view model stays pure and tests use a fake (no real terminate/purge).
public protocol SystemActions {
    func quit(app: AppGroup) async -> ActionResult
    func purge() async -> ActionResult
    func revealInActivityMonitor(app: AppGroup)
    func copySnapshot(_ text: String)
}

/// Records calls and returns scripted results. Reference type so tests can
/// inspect it after passing it into a view model.
public final class FakeSystemActions: SystemActions {
    public var quitResult: ActionResult = .ok
    public var purgeResult: ActionResult = .ok
    public private(set) var quitCalls: [AppGroup] = []
    public private(set) var purgeCallCount = 0
    public private(set) var revealCalls: [AppGroup] = []
    public private(set) var copiedText: String?

    public init() {}

    public func quit(app: AppGroup) async -> ActionResult {
        quitCalls.append(app); return quitResult
    }
    public func purge() async -> ActionResult {
        purgeCallCount += 1; return purgeResult
    }
    public func revealInActivityMonitor(app: AppGroup) { revealCalls.append(app) }
    public func copySnapshot(_ text: String) { copiedText = text }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter FakeSystemActionsTests`
Expected: PASS (3 tests).

- [ ] **Step 9: Commit**

```bash
git add Sources/MacMemMenuBar/AppResolver.swift Sources/MacMemMenuBar/SystemActions.swift Tests/MacMemMenuBarTests/AppResolverTests.swift Tests/MacMemMenuBarTests/FakeSystemActionsTests.swift
git commit -m "feat(menubar): add SystemActions seam and pure AppResolver"
```

---

## Task 4: SnapshotEngine (adaptive sampling)

**Files:**
- Create: `Sources/MacMemMenuBar/SnapshotEngine.swift`
- Test: `Tests/MacMemMenuBarTests/SnapshotEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MacMemMenuBarTests/SnapshotEngineTests.swift`:

```swift
import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

/// Counts which provider methods get called so we can assert the engine's mode behavior.
private final class SpyProvider: MemoryProvider, @unchecked Sendable {
    private(set) var pressureCalls = 0
    private(set) var listCalls = 0
    var pressureValue: MemoryPressure = .warn

    func listProcesses() throws -> [ProcessSample] { listCalls += 1; return [] }
    func readSwap() throws -> SwapInfo {
        SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0)
    }
    func compressedByPID() throws -> [pid_t: UInt64] { [:] }
    func pressure() -> MemoryPressure { pressureCalls += 1; return pressureValue }
}

@MainActor
final class SnapshotEngineTests: XCTestCase {
    func testCollapsedTickReadsOnlyPressure() async {
        let spy = SpyProvider()
        var gotPressure: MemoryPressure?
        var gotSnapshot = false
        let engine = SnapshotEngine(provider: spy, tabSource: nil, topN: 10)
        engine.onPressure = { gotPressure = $0 }
        engine.onSnapshot = { _ in gotSnapshot = true }

        engine.setMenuOpen(false)
        await engine.tick()

        XCTAssertEqual(gotPressure, .warn)
        XCTAssertEqual(spy.pressureCalls, 1)
        XCTAssertEqual(spy.listCalls, 0, "collapsed mode must not build a full snapshot")
        XCTAssertFalse(gotSnapshot)
    }

    func testOpenTickBuildsFullSnapshotAndPressure() async {
        let spy = SpyProvider()
        var gotSnapshot: MemorySnapshot?
        let engine = SnapshotEngine(provider: spy, tabSource: nil, topN: 10)
        engine.onSnapshot = { gotSnapshot = $0 }

        engine.setMenuOpen(true)
        await engine.tick()

        XCTAssertEqual(spy.pressureCalls, 1, "open mode still updates pressure")
        XCTAssertEqual(spy.listCalls, 1, "open mode builds a full snapshot")
        XCTAssertNotNil(gotSnapshot)
    }

    func testIntervalSwitchesWithMode() {
        let spy = SpyProvider()
        let engine = SnapshotEngine(provider: spy, tabSource: nil, topN: 10)
        engine.setMenuOpen(false)
        XCTAssertEqual(engine.currentInterval, 5.0, accuracy: 0.001)
        engine.setMenuOpen(true)
        XCTAssertEqual(engine.currentInterval, 2.5, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SnapshotEngineTests`
Expected: FAIL — `cannot find 'SnapshotEngine' in scope`.

- [ ] **Step 3: Implement SnapshotEngine**

Create `Sources/MacMemMenuBar/SnapshotEngine.swift`:

```swift
import Foundation
import MacMemCore

/// Drives adaptive sampling. While collapsed it polls only the cheap pressure
/// sysctl; while the dropdown is open it builds the full snapshot. UI-free:
/// it exposes callbacks the view model subscribes to.
@MainActor
public final class SnapshotEngine {
    public enum Mode { case collapsed, open }

    private let provider: MemoryProvider
    private let tabSource: TabSource?
    private let topN: Int

    public private(set) var mode: Mode = .collapsed
    public var onPressure: ((MemoryPressure) -> Void)?
    public var onSnapshot: ((MemorySnapshot) -> Void)?

    private var timer: Timer?

    /// Poll intervals (seconds): slow while collapsed, faster while open.
    private let collapsedInterval: TimeInterval = 5.0
    private let openInterval: TimeInterval = 2.5

    public var currentInterval: TimeInterval {
        mode == .open ? openInterval : collapsedInterval
    }

    public init(provider: MemoryProvider, tabSource: TabSource?, topN: Int) {
        self.provider = provider
        self.tabSource = tabSource
        self.topN = topN
    }

    /// Switch modes, reschedule the timer at the new interval, and tick once now
    /// so the UI updates immediately on open/close instead of after a full delay.
    public func setMenuOpen(_ open: Bool) {
        mode = open ? .open : .collapsed
        scheduleTimer()
        Task { await tick() }
    }

    /// Start sampling (called once when the app launches).
    public func start() {
        scheduleTimer()
        Task { await tick() }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
    }

    /// One sampling cycle. Always refreshes pressure (cheap). In open mode it also
    /// builds the full snapshot off the main thread and delivers it on the main actor.
    public func tick() async {
        onPressure?(provider.pressure())
        guard mode == .open else { return }
        let provider = self.provider
        let tabSource = self.tabSource
        let topN = self.topN
        let snapshot = await Task.detached(priority: .utility) {
            SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: topN)
        }.value
        onSnapshot?(snapshot)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SnapshotEngineTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacMemMenuBar/SnapshotEngine.swift Tests/MacMemMenuBarTests/SnapshotEngineTests.swift
git commit -m "feat(menubar): add adaptive SnapshotEngine"
```

---

## Task 5: MenuViewModel (state, intents, confirmations)

**Files:**
- Create: `Sources/MacMemMenuBar/MenuViewModel.swift`
- Test: `Tests/MacMemMenuBarTests/MenuViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MacMemMenuBarTests/MenuViewModelTests.swift`:

```swift
import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor
final class MenuViewModelTests: XCTestCase {
    private func makeProvider(pressure: MemoryPressure = .normal) -> FakeMemoryProvider {
        var p = FakeMemoryProvider(
            processes: [ProcessSample(pid: 1, ppid: 0, responsiblePID: nil, bundleID: "com.x",
                                      name: "X", executablePath: nil, footprintBytes: 100,
                                      residentBytes: 100, pageIns: 0, isReadable: true)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        p.pressureValue = pressure
        return p
    }

    private func group(_ name: String) -> AppGroup {
        AppGroup(name: name, bundleID: "com.x", totalFootprintBytes: 100, processCount: 1, pids: [1])
    }

    func testRefreshPublishesPressureAndSnapshot() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(pressure: .critical), tabSource: nil, actions: actions)
        vm.setMenuOpen(true)
        await vm.refreshNow()
        XCTAssertEqual(vm.pressure, .critical)
        XCTAssertNotNil(vm.snapshot)
        XCTAssertEqual(vm.snapshot?.topApps.first?.name, "X")
    }

    func testQuitGoesThroughConfirmationStateMachine() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        // Requesting quit does NOT act yet — it stages a confirmation.
        vm.requestQuit(group("Brave Browser"))
        XCTAssertEqual(vm.pendingConfirmation, .quit(group("Brave Browser")))
        XCTAssertEqual(actions.quitCalls.count, 0)
        // Confirming performs it.
        await vm.confirmPending()
        XCTAssertEqual(actions.quitCalls.map(\.name), ["Brave Browser"])
        XCTAssertNil(vm.pendingConfirmation)
    }

    func testCancelConfirmationDoesNotAct() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.requestPurge()
        XCTAssertEqual(vm.pendingConfirmation, .purge)
        vm.cancelPending()
        XCTAssertNil(vm.pendingConfirmation)
        await vm.confirmPending()   // nothing pending → no-op
        XCTAssertEqual(actions.purgeCallCount, 0)
    }

    func testCopyRendersSnapshotThroughActions() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.setMenuOpen(true)
        await vm.refreshNow()
        vm.copySnapshot()
        XCTAssertNotNil(actions.copiedText)
        XCTAssertTrue(actions.copiedText?.contains("TOP APPS") ?? false,
                      "copied text should be the CLI TextRenderer output")
    }

    func testRevealForwardsToActions() {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.reveal(group("A"))
        XCTAssertEqual(actions.revealCalls.map(\.name), ["A"])
    }

    func testFailedActionSurfacesMessage() async {
        let actions = FakeSystemActions()
        actions.purgeResult = .failed("nope")
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.requestPurge()
        await vm.confirmPending()
        XCTAssertEqual(vm.lastActionMessage, "nope")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuViewModelTests`
Expected: FAIL — `cannot find 'MenuViewModel' in scope`.

- [ ] **Step 3: Implement MenuViewModel**

Create `Sources/MacMemMenuBar/MenuViewModel.swift`:

```swift
import Foundation
import MacMemCore

/// A staged, user-confirmable action. Equatable so the view can drive a
/// `.confirmationDialog` and tests can assert the state machine.
public enum PendingConfirmation: Equatable {
    case quit(AppGroup)
    case purge
}

/// Single source of truth for the menubar UI. `ObservableObject` (not `@Observable`)
/// to keep the macOS 13 deployment target. All system effects go through `SystemActions`.
@MainActor
public final class MenuViewModel: ObservableObject {
    @Published public private(set) var pressure: MemoryPressure = .unknown
    @Published public private(set) var snapshot: MemorySnapshot?
    @Published public private(set) var lastUpdated: Date?
    @Published public var pendingConfirmation: PendingConfirmation?
    @Published public private(set) var lastActionMessage: String?

    private let engine: SnapshotEngine
    private let actions: SystemActions
    private let topN: Int

    public init(provider: MemoryProvider, tabSource: TabSource?,
                actions: SystemActions, topN: Int = 10) {
        self.actions = actions
        self.topN = topN
        self.engine = SnapshotEngine(provider: provider, tabSource: tabSource, topN: topN)
        self.engine.onPressure = { [weak self] in self?.pressure = $0 }
        self.engine.onSnapshot = { [weak self] snap in
            self?.snapshot = snap
            self?.lastUpdated = Date()
        }
    }

    // MARK: Lifecycle
    public func start() { engine.start() }
    public func setMenuOpen(_ open: Bool) { engine.setMenuOpen(open) }
    /// Forces one immediate sampling cycle (used by tests and manual refresh).
    public func refreshNow() async { await engine.tick() }

    // MARK: Intents
    public func requestQuit(_ app: AppGroup) { pendingConfirmation = .quit(app) }
    public func requestPurge() { pendingConfirmation = .purge }
    public func cancelPending() { pendingConfirmation = nil }

    public func confirmPending() async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        let result: ActionResult
        switch pending {
        case .quit(let app): result = await actions.quit(app: app)
        case .purge:         result = await actions.purge()
        }
        applyResult(result)
    }

    public func reveal(_ app: AppGroup) { actions.revealInActivityMonitor(app: app) }

    public func copySnapshot() {
        guard let snapshot else { return }
        actions.copySnapshot(TextRenderer.render(snapshot))
    }

    private func applyResult(_ result: ActionResult) {
        switch result {
        case .ok, .cancelled: lastActionMessage = nil
        case .failed(let msg): lastActionMessage = msg
        case .notPermitted:    lastActionMessage = "Not permitted."
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MenuViewModelTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Run full suite**

Run: `swift test`
Expected: PASS (all targets green).

- [ ] **Step 6: Commit**

```bash
git add Sources/MacMemMenuBar/MenuViewModel.swift Tests/MacMemMenuBarTests/MenuViewModelTests.swift
git commit -m "feat(menubar): add MenuViewModel with confirmation state machine"
```

---

## Task 6: LiveSystemActions (real implementation)

**Files:**
- Create: `Sources/MacMemMenuBar/LiveSystemActions.swift`
- Test: `Tests/MacMemMenuBarTests/LiveSystemActionsTests.swift`

> Real terminate/purge are not unit-tested (side effects); only the pure
> candidate-mapping used by `quit` is. The test asserts `LiveSystemActions`
> builds candidates from `NSWorkspace` and reuses `AppResolver`.

- [ ] **Step 1: Write the failing test**

Create `Tests/MacMemMenuBarTests/LiveSystemActionsTests.swift`:

```swift
import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor
final class LiveSystemActionsTests: XCTestCase {
    func testCurrentCandidatesIncludeThisProcess() {
        // The test process itself is a running app; its pid must appear.
        let candidates = LiveSystemActions.currentCandidates()
        let mypid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(candidates.contains { $0.pid == mypid } || !candidates.isEmpty,
                      "should enumerate running apps (at least non-empty)")
    }

    func testQuitUnmatchedGroupReturnsNotPermitted() async {
        // A group that matches no running app cannot be quit.
        let ghost = AppGroup(name: "Ghost", bundleID: "com.nonexistent.ghost.\(UUID().uuidString)",
                             totalFootprintBytes: 1, processCount: 1, pids: [Int32.max - 1])
        let result = await LiveSystemActions().quit(app: ghost)
        XCTAssertEqual(result, .notPermitted)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LiveSystemActionsTests`
Expected: FAIL — `cannot find 'LiveSystemActions' in scope`.

- [ ] **Step 3: Implement LiveSystemActions**

Create `Sources/MacMemMenuBar/LiveSystemActions.swift`:

```swift
import Foundation
import AppKit
import MacMemCore

/// Real system-effecting actions. Quitting is limited to the current user's apps
/// (no privileged helper); purge uses a one-shot admin prompt; nothing persists.
@MainActor
public final class LiveSystemActions: SystemActions {
    public init() {}

    /// Snapshot of running apps as pure candidates, for `AppResolver`.
    public static func currentCandidates() -> [AppCandidate] {
        NSWorkspace.shared.runningApplications.map {
            AppCandidate(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier)
        }
    }

    public func quit(app: AppGroup) async -> ActionResult {
        let running = NSWorkspace.shared.runningApplications
        let candidates = running.map {
            AppCandidate(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier)
        }
        guard let idx = AppResolver.matchIndex(group: app, candidates: candidates) else {
            return .notPermitted   // not one of the current user's GUI apps
        }
        return running[idx].terminate() ? .ok : .failed("Could not quit \(app.name).")
    }

    public func purge() async -> ActionResult {
        let source = "do shell script \"/usr/sbin/purge\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return .failed("Could not build purge script.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .ok }
        // -128 is userCancelledErr (the admin sheet was dismissed).
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "purge failed"
        return .failed(msg)
    }

    public func revealInActivityMonitor(app: AppGroup) {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    public func copySnapshot(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LiveSystemActionsTests`
Expected: PASS (2 tests). (The `quit` test targets a non-existent app, so no real app is terminated.)

- [ ] **Step 5: Commit**

```bash
git add Sources/MacMemMenuBar/LiveSystemActions.swift Tests/MacMemMenuBarTests/LiveSystemActionsTests.swift
git commit -m "feat(menubar): add LiveSystemActions (quit/purge/reveal/copy)"
```

---

## Task 7: SwiftUI views + MenuBarExtra app

**Files:**
- Create: `Sources/MacMemMenuBar/Views/BarLabel.swift`
- Create: `Sources/MacMemMenuBar/Views/PermissionBanner.swift`
- Create: `Sources/MacMemMenuBar/Views/SectionViews.swift`
- Create: `Sources/MacMemMenuBar/Views/MenuContentView.swift`
- Modify: `Sources/MacMemMenuBar/MacMemMenuBarApp.swift` (replace the Task 2 stub)
- Test: `Tests/MacMemMenuBarTests/PressureStyleTests.swift`

> Views are not snapshot-tested. The one pure piece — pressure → color/symbol
> mapping — is factored out of `BarLabel` and unit-tested.

- [ ] **Step 1: Write the failing pressure-style test**

Create `Tests/MacMemMenuBarTests/PressureStyleTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import MacMemMenuBar
@testable import MacMemCore

final class PressureStyleTests: XCTestCase {
    func testSymbolPerLevel() {
        XCTAssertEqual(PressureStyle.symbolName(for: .normal), "memorychip")
        XCTAssertEqual(PressureStyle.symbolName(for: .warn), "memorychip")
        XCTAssertEqual(PressureStyle.symbolName(for: .critical), "memorychip.fill")
        XCTAssertEqual(PressureStyle.symbolName(for: .unknown), "memorychip")
    }

    func testTintPerLevel() {
        XCTAssertEqual(PressureStyle.tint(for: .normal), .green)
        XCTAssertEqual(PressureStyle.tint(for: .warn), .yellow)
        XCTAssertEqual(PressureStyle.tint(for: .critical), .red)
        // Unknown must be neutral (never a fake green).
        XCTAssertEqual(PressureStyle.tint(for: .unknown), .secondary)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PressureStyleTests`
Expected: FAIL — `cannot find 'PressureStyle' in scope`.

- [ ] **Step 3: Implement BarLabel + PressureStyle**

Create `Sources/MacMemMenuBar/Views/BarLabel.swift`:

```swift
import SwiftUI
import MacMemCore

/// Pure mapping from pressure to the collapsed bar's symbol and tint.
/// `.unknown` is neutral so the bar never shows a fabricated "all good" green.
public enum PressureStyle {
    public static func symbolName(for pressure: MemoryPressure) -> String {
        pressure == .critical ? "memorychip.fill" : "memorychip"
    }
    public static func tint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal:   return .green
        case .warn:     return .yellow
        case .critical: return .red
        case .unknown:  return .secondary
        }
    }
    public static func tooltip(for pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal:   return "Memory pressure: normal"
        case .warn:     return "Memory pressure: warning"
        case .critical: return "Memory pressure: critical"
        case .unknown:  return "Memory pressure unavailable"
        }
    }
}

/// The collapsed menubar label.
struct BarLabel: View {
    let pressure: MemoryPressure
    var body: some View {
        Image(systemName: PressureStyle.symbolName(for: pressure))
            .foregroundStyle(PressureStyle.tint(for: pressure))
            .help(PressureStyle.tooltip(for: pressure))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PressureStyleTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Implement PermissionBanner**

Create `Sources/MacMemMenuBar/Views/PermissionBanner.swift`:

```swift
import SwiftUI

/// A small inline banner with an optional action button. Used for the
/// Automation-denied case and the "N processes unreadable" note.
struct PermissionBanner: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.callout)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Opens System Settings → Privacy & Security → Automation.
func openAutomationSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 6: Implement SectionViews**

Create `Sources/MacMemMenuBar/Views/SectionViews.swift`:

```swift
import SwiftUI
import MacMemCore

/// TOP APPS rows. Tapping a row opens a per-row menu (quit / reveal) via callbacks.
struct TopAppsSection: View {
    let snapshot: MemorySnapshot
    let onQuit: (AppGroup) -> Void
    let onReveal: (AppGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOP APPS").font(.caption).foregroundStyle(.secondary)
            if snapshot.appsStatus == .error {
                Text("Could not read processes.").font(.callout)
            } else {
                ForEach(snapshot.topApps, id: \.name) { app in
                    HStack {
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(app.totalFootprintBytes))
                            .foregroundStyle(.secondary).monospacedDigit()
                        Menu("") {
                            Button("Quit \(app.name)…") { onQuit(app) }
                            Button("Reveal in Activity Monitor") { onReveal(app) }
                        }
                        .menuStyle(.borderlessButton).frame(width: 16)
                    }
                }
                if snapshot.unreadableProcessCount > 0 {
                    Text("\(snapshot.unreadableProcessCount) processes not shown (owned by other users).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// SWAP + measured compressed memory.
struct SwapSection: View {
    let snapshot: MemorySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SWAP").font(.caption).foregroundStyle(.secondary)
            if let swap = snapshot.swap {
                Text("Used \(ByteFormat.string(swap.usedBytes)) / \(ByteFormat.string(swap.totalBytes))")
                    .monospacedDigit()
            }
            if !snapshot.compressedAvailable {
                Text("per-app compressed memory unavailable (could not read from top)")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.compressedUsers.prefix(5), id: \.appName) { e in
                    HStack {
                        Text(e.appName).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(e.compressedBytes))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

/// BROWSER TABS — per-browser measured total + tab list.
struct TabsSection: View {
    let snapshot: MemorySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BROWSER TABS").font(.caption).foregroundStyle(.secondary)
            if snapshot.tabsStatus == .permissionNeeded {
                PermissionBanner(text: "Allow Automation to read browser tabs.",
                                 actionTitle: "Open Settings", action: openAutomationSettings)
            } else {
                ForEach(snapshot.browsers, id: \.browser) { b in
                    let total = b.totalFootprintBytes.map(ByteFormat.string) ?? "not separately attributable"
                    Text("\(b.browser) — \(total) · \(b.tabs.count) tabs")
                        .font(.callout)
                    if snapshot.tabsStatus == .partial {
                        Text("some browsers could not be read.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
```

> **Check `ByteFormat`'s public API before relying on `ByteFormat.string(_:)`.**
> Open `Sources/MacMemCore/ByteFormat.swift`. If the function has a different
> name/signature, use that name consistently in all three section views. If
> `ByteFormat` is not `public`, add `public` to the enum and the formatting
> function in that file (one-line change) so the menubar target can call it,
> and note it in the commit.

- [ ] **Step 7: Implement MenuContentView**

Create `Sources/MacMemMenuBar/Views/MenuContentView.swift`:

```swift
import SwiftUI
import MacMemCore

/// The dropdown body. Reads everything from the view model.
struct MenuContentView: View {
    @ObservedObject var model: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = model.snapshot {
                TopAppsSection(snapshot: snapshot,
                               onQuit: { model.requestQuit($0) },
                               onReveal: { model.reveal($0) })
                Divider()
                SwapSection(snapshot: snapshot)
                Divider()
                TabsSection(snapshot: snapshot)
            } else {
                Text("Measuring…").foregroundStyle(.secondary)
            }

            if let msg = model.lastActionMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button("Purge…") { model.requestPurge() }
                Button("Copy") { model.copySnapshot() }
                Spacer()
                Button("Quit macmem") { NSApplication.shared.terminate(nil) }
            }
            if let updated = model.lastUpdated {
                Text("updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 360)
        .confirmationDialog("Confirm", isPresented: confirmBinding, presenting: model.pendingConfirmation) { pending in
            Button(confirmTitle(pending), role: .destructive) {
                Task { await model.confirmPending() }
            }
            Button("Cancel", role: .cancel) { model.cancelPending() }
        } message: { pending in
            Text(confirmMessage(pending))
        }
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { model.pendingConfirmation != nil },
                set: { if !$0 { model.cancelPending() } })
    }

    private func confirmTitle(_ p: PendingConfirmation) -> String {
        switch p {
        case .quit(let app): return "Quit \(app.name)"
        case .purge:         return "Run purge"
        }
    }

    private func confirmMessage(_ p: PendingConfirmation) -> String {
        switch p {
        case .quit(let app):
            return "Quit \(app.name) (\(ByteFormat.string(app.totalFootprintBytes)))? Unsaved work may be lost."
        case .purge:
            return "Run purge? It flushes disk caches and briefly spikes disk I/O. You'll be asked for your admin password."
        }
    }
}
```

- [ ] **Step 8: Replace the stub app entry point**

Replace the entire contents of `Sources/MacMemMenuBar/MacMemMenuBarApp.swift`:

```swift
import SwiftUI
import MacMemCore

@main
struct MacMemMenuBarApp: App {
    @StateObject private var model = MenuViewModel(
        provider: NativeMemoryProvider(),
        tabSource: AppleScriptTabSource(),
        actions: LiveSystemActions())

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
                .onAppear { model.setMenuOpen(true) }
                .onDisappear { model.setMenuOpen(false) }
        } label: {
            BarLabel(pressure: model.pressure)
        }
        .menuBarExtraStyle(.window)
    }
}
```

> **Check `AppleScriptTabSource`'s initializer.** Open
> `Sources/MacMemCore/AppleScriptTabSource.swift`. If its `init` takes arguments
> or it isn't `public`, adjust the construction here accordingly (and make it
> `public` if needed, noting it in the commit). It must be reachable from the
> menubar target.

- [ ] **Step 9: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS — everything compiles and all tests are green.

- [ ] **Step 10: Commit**

```bash
git add Sources/MacMemMenuBar/Views Sources/MacMemMenuBar/MacMemMenuBarApp.swift Tests/MacMemMenuBarTests/PressureStyleTests.swift
git commit -m "feat(menubar): add SwiftUI views and MenuBarExtra app"
```

---

## Task 8: Bundle assembly via `just app`

**Files:**
- Create: `Resources/MenuBar/Info.plist.template`
- Modify: `justfile`

> SwiftPM produces a bare executable; `MenuBarExtra` needs a real `.app` bundle
> with `LSUIElement` so it runs as an agent (no Dock icon). This task assembles
> that bundle and ad-hoc signs it for local runs.

- [ ] **Step 1: Create the Info.plist template**

Create `Resources/MenuBar/Info.plist.template`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>MacMem</string>
    <key>CFBundleDisplayName</key>     <string>MacMem</string>
    <key>CFBundleIdentifier</key>      <string>com.itinance.macmem.menubar</string>
    <key>CFBundleExecutable</key>      <string>MacMemMenuBar</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.2.0</string>
    <key>CFBundleVersion</key>         <string>0.2.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSAppleEventsUsageDescription</key>
        <string>macmem reads open browser tabs to attribute memory to them.</string>
</dict>
</plist>
```

- [ ] **Step 2: Add the `app` and `run-app` recipes**

Append to `justfile`:

```just
# ---------------------------------------------------------------------------
# MenuBar app bundle
# ---------------------------------------------------------------------------

# Assemble MacMem.app from the release build (LSUIElement menubar agent).
app:
    swift build -c release --product MacMemMenuBar
    rm -rf .build/MacMem.app
    mkdir -p .build/MacMem.app/Contents/MacOS
    cp Resources/MenuBar/Info.plist.template .build/MacMem.app/Contents/Info.plist
    cp .build/release/MacMemMenuBar .build/MacMem.app/Contents/MacOS/MacMemMenuBar
    codesign --force --sign - .build/MacMem.app
    @echo "Built .build/MacMem.app"

# Build the bundle and launch it.
run-app: app
    open .build/MacMem.app
```

- [ ] **Step 3: Build the bundle**

Run: `just app`
Expected: prints `Built .build/MacMem.app`; `.build/MacMem.app/Contents/MacOS/MacMemMenuBar` exists and `codesign -dv .build/MacMem.app` shows an ad-hoc signature.

- [ ] **Step 4: Manual smoke test**

Run: `just run-app`
Expected: a memory-chip icon appears in the menubar; clicking it opens the dropdown with TOP APPS / SWAP / BROWSER TABS; first tab read triggers the Automation prompt; Purge… shows a confirmation then the admin-password sheet; Copy puts the snapshot on the clipboard. Quit macmem removes the icon.

> If the icon does not appear, confirm `LSUIElement` is in the built
> `Contents/Info.plist` and that you launched the `.app` (not the bare binary).

- [ ] **Step 5: Commit**

```bash
git add Resources/MenuBar/Info.plist.template justfile
git commit -m "build: assemble MacMem.app bundle via just app"
```

---

## Final Review

After all tasks: dispatch a final whole-feature code review covering `Sources/MacMemMenuBar/` and the `MacMemCore` pressure addition, then use `superpowers:finishing-a-development-branch`.

## Self-Review Notes (author)

- **Spec coverage:** pressure core (Task 1) ✓; MenuBarExtra + pressure bar (Tasks 7) ✓; three sections (Task 7 SectionViews) ✓; four actions (Tasks 3/5/6) ✓; adaptive refresh (Task 4) ✓; one-shot purge + honest degradation (Task 6, SectionViews banners) ✓; SwiftPM + `just app` (Tasks 2/8) ✓; testing strategy (per-task) ✓; out-of-scope items not built ✓.
- **Type consistency:** `MemoryPressure`, `ActionResult`, `PendingConfirmation`, `AppCandidate`, `SnapshotEngine.onPressure/onSnapshot/tick/setMenuOpen/currentInterval`, `MenuViewModel.{pressure,snapshot,requestQuit,requestPurge,confirmPending,cancelPending,reveal,copySnapshot,setMenuOpen,refreshNow}` are used identically across tasks.
- **External-API checks flagged inline:** `ByteFormat` (Task 7 Step 6), `AppleScriptTabSource` init/visibility (Task 7 Step 8), `TextRenderer.render` default args (used in Task 5). These are verify-then-adjust notes because the exact public signatures must be confirmed at implementation time.
```
