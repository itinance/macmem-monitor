# Measured Compressed Memory Implementation Plan

> **⚠️ SUPERSEDED (2026-06-07):** This plan's data source — `task_info(TASK_VM_INFO).compressed` via `task_for_pid` — proved unusable without `sudo` (it only reads our own descendants, so it measured almost nothing in practice). The shipped implementation instead parses `/usr/bin/top -l 1 -stats pid,cmprs` (`TopCompressedSource.swift`), which reads compressed memory for all processes without sudo. The model/aggregator/renderer design below is otherwise accurate. Kept as a historical record of the approach and the reasoning that led to it.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the misleading page-in-based "estimated swap" attribution with **measured** per-process compressed memory read via `task_info(TASK_VM_INFO).compressed`.

**Architecture:** Per-process compressed bytes are gathered in `NativeMemoryProvider` via `task_for_pid` + `task_info`. A new `CompressedMemoryAggregator` sums them per app group and ranks them. The SWAP section keeps the real system swap totals (`sysctl vm.swapusage`) but its contributor list now shows measured compressed memory labelled `[measured]`, plus a coverage footer when some processes could not be read (need sudo).

**Tech Stack:** Swift 6.3.1, SwiftPM, Darwin/Mach (`task_for_pid`, `task_info`, `TASK_VM_INFO`), XCTest.

**Why the old approach was wrong:** `ri_pageins` is a lifetime disk-read counter, not swap-ins. The old `estimatedSwapBytes` was fabricated as `proportional_share × total_used_swap`, so it always summed to ~all swap regardless of reality and attributed huge GB to apps that held no swap. macOS exposes no public per-process *swap* counter, but `task_info(TASK_VM_INFO).compressed` gives the real per-process *compressed* footprint — the memory the compressor holds and the direct precursor to swap. That is what we now measure and report.

**Permission reality:** `task_for_pid` works for our own process always, for other same-user processes generally only under `sudo`, and never for some hardened Apple binaries. So without sudo this list will be sparse; the coverage footer tells the user to run with sudo.

---

### Task 1: Measure and report per-process compressed memory

**Files:**
- Modify: `Sources/MacMemCore/Models.swift`
- Modify: `Sources/MacMemCore/NativeMemoryProvider.swift`
- Rename + rewrite: `Sources/MacMemCore/SwapEstimator.swift` → `Sources/MacMemCore/CompressedMemoryAggregator.swift`
- Modify: `Sources/MacMemCore/SnapshotBuilder.swift`
- Modify: `Sources/MacMemCore/TextRenderer.swift`
- Rename + rewrite test: `Tests/MacMemCoreTests/SwapEstimatorTests.swift` → `Tests/MacMemCoreTests/CompressedMemoryAggregatorTests.swift`
- Modify: `Tests/MacMemCoreTests/RendererTests.swift`
- Modify: `Tests/MacMemCoreTests/SnapshotBuilderTests.swift`

This is one cohesive change. Follow TDD where practical, but the data-model rename means you must update several call sites in the same pass to keep the build green — that's expected.

#### Model changes (`Models.swift`)

1. Add to `ProcessSample` a new stored property `compressedBytes: UInt64?` (nil = could not measure this process's compressed footprint — `task_for_pid` denied). Add it to the initializer **with a default of `nil`** so existing call sites keep compiling:

```swift
public struct ProcessSample: Sendable, Equatable, Codable {
    public let pid: Int32
    public let ppid: Int32
    public let responsiblePID: Int32?
    public let bundleID: String?
    public let name: String
    public let executablePath: String?
    public let footprintBytes: UInt64
    public let residentBytes: UInt64
    public let pageIns: UInt64
    /// Per-process compressed-memory footprint in bytes, measured via
    /// task_info(TASK_VM_INFO).compressed. nil when task_for_pid was denied
    /// (other-user / hardened processes without sudo). This is the swap precursor.
    public let compressedBytes: UInt64?
    public let isReadable: Bool

    public init(pid: Int32, ppid: Int32, responsiblePID: Int32?, bundleID: String?,
                name: String, executablePath: String?, footprintBytes: UInt64,
                residentBytes: UInt64, pageIns: UInt64, compressedBytes: UInt64? = nil,
                isReadable: Bool) {
        self.pid = pid; self.ppid = ppid; self.responsiblePID = responsiblePID
        self.bundleID = bundleID; self.name = name; self.executablePath = executablePath
        self.footprintBytes = footprintBytes; self.residentBytes = residentBytes
        self.pageIns = pageIns; self.compressedBytes = compressedBytes; self.isReadable = isReadable
    }
}
```

2. Replace the `SwapCulprit` struct entirely with `CompressedMemoryEntry` (this is measured, so no `score`/`confidence`/`estimated` anything):

```swift
/// A measured per-app compressed-memory total. Unlike the old SwapCulprit this is
/// NOT an estimate — it is the sum of task_info(TASK_VM_INFO).compressed across the
/// app's readable processes.
public struct CompressedMemoryEntry: Sendable, Equatable, Codable {
    public let appName: String
    public let bundleID: String?
    public let compressedBytes: UInt64

    public init(appName: String, bundleID: String?, compressedBytes: UInt64) {
        self.appName = appName; self.bundleID = bundleID
        self.compressedBytes = compressedBytes
    }
}
```

3. In `MemorySnapshot`, rename `swapCulprits: [SwapCulprit]` → `compressedUsers: [CompressedMemoryEntry]` and add `compressedUnreadableCount: Int`. Update the initializer (keep `compressedUnreadableCount` with a default of `0` for convenience):

```swift
public struct MemorySnapshot: Sendable, Equatable, Codable {
    public let topApps: [AppGroup]
    public let appsStatus: SectionStatus
    public let unreadableProcessCount: Int
    public let swap: SwapInfo?
    public let compressedUsers: [CompressedMemoryEntry]
    public let compressedUnreadableCount: Int
    public let swapStatus: SectionStatus
    public let topTabs: [BrowserTab]
    public let tabsStatus: SectionStatus

    public init(topApps: [AppGroup], appsStatus: SectionStatus, unreadableProcessCount: Int,
                swap: SwapInfo?, compressedUsers: [CompressedMemoryEntry],
                compressedUnreadableCount: Int = 0, swapStatus: SectionStatus,
                topTabs: [BrowserTab], tabsStatus: SectionStatus) {
        self.topApps = topApps; self.appsStatus = appsStatus
        self.unreadableProcessCount = unreadableProcessCount
        self.swap = swap; self.compressedUsers = compressedUsers
        self.compressedUnreadableCount = compressedUnreadableCount
        self.swapStatus = swapStatus
        self.topTabs = topTabs; self.tabsStatus = tabsStatus
    }
}
```

#### Provider changes (`NativeMemoryProvider.swift`)

4. Add a static helper that measures compressed bytes for a pid (returns nil on denial). `import Darwin` is already present:

```swift
/// Measured per-process compressed memory via task_info(TASK_VM_INFO).
/// Returns nil when task_for_pid is denied (other-user/hardened process without sudo).
private static func compressed(for pid: pid_t) -> UInt64? {
    var task: task_t = 0
    guard task_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS else { return nil }
    defer { mach_port_deallocate(mach_task_self_, task) }
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let rc = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(task, task_flavor_t(TASK_VM_INFO), intPtr, &count)
        }
    }
    guard rc == KERN_SUCCESS else { return nil }
    return UInt64(info.compressed)
}
```

5. In `listProcesses()`, compute `let comp = Self.compressed(for: pid)` once and pass `compressedBytes: comp` into BOTH the readable and the unreadable `ProcessSample(...)` constructions. (Compressed readability is independent of rusage readability, so attempt it in both branches.)

#### Aggregator (`CompressedMemoryAggregator.swift`, was `SwapEstimator.swift`)

6. `git mv Sources/MacMemCore/SwapEstimator.swift Sources/MacMemCore/CompressedMemoryAggregator.swift` and replace its contents:

```swift
import Foundation

/// Aggregates MEASURED per-process compressed memory into per-app totals and ranks them.
/// This is not an estimate: it sums task_info(TASK_VM_INFO).compressed across each app's
/// processes. Processes whose compressed footprint could not be measured (nil) contribute
/// nothing. Groups whose measured total is zero are excluded.
public struct CompressedMemoryAggregator {
    public init() {}

    public func entries(groups: [AppGroup], samples: [ProcessSample], topN: Int = 10) -> [CompressedMemoryEntry] {
        let limit = max(0, topN)
        let compressedByPID = Dictionary(
            samples.compactMap { s in s.compressedBytes.map { (s.pid, $0) } },
            uniquingKeysWith: { a, _ in a })

        let scored: [(group: AppGroup, total: UInt64)] = groups.compactMap { g in
            let total = g.pids.reduce(UInt64(0)) { $0 + (compressedByPID[$1] ?? 0) }
            return total > 0 ? (g, total) : nil
        }

        return scored
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { CompressedMemoryEntry(appName: $0.group.name, bundleID: $0.group.bundleID,
                                         compressedBytes: $0.total) }
    }
}
```

#### Builder (`SnapshotBuilder.swift`)

7. In the swap section, keep reading swap totals, but compute compressed users from the aggregator (it does NOT need `swap`), and count unmeasurable processes. Replace the swap-section block and the final return:

```swift
        // --- Swap totals + measured compressed memory ---
        var swap: SwapInfo?
        var compressedUsers: [CompressedMemoryEntry] = []
        var swapStatus: SectionStatus = .ok
        if includeSwap {
            do {
                swap = try provider.readSwap()
            } catch {
                swapStatus = .error
            }
            // Compressed memory is meaningful even when used swap is 0 (the compressor
            // holds compressed pages in RAM before any swap-out), so compute it regardless.
            compressedUsers = CompressedMemoryAggregator().entries(groups: topApps, samples: samples, topN: topN)
        }
        // Processes whose compressed footprint we could not read (task_for_pid denied).
        let compressedUnreadable = samples.filter { $0.compressedBytes == nil }.count
```

   And the return:

```swift
        return MemorySnapshot(topApps: topApps, appsStatus: appsStatus,
                              unreadableProcessCount: unreadable, swap: swap,
                              compressedUsers: compressedUsers,
                              compressedUnreadableCount: compressedUnreadable,
                              swapStatus: swapStatus,
                              topTabs: topTabs, tabsStatus: tabsStatus)
```

   Note: `samples` is `[]` when the apps section threw, so `compressedUnreadable` is `0` in that case — fine.

#### Renderer (`TextRenderer.swift`)

8. Replace the body of the `if includeSwap {` block (lines ~40-57) with:

```swift
        if includeSwap {
            lines.append("")
            lines.append("== SWAP ==")
            if let swap = snap.swap {
                lines.append("Used \(ByteFormat.string(swap.usedBytes)) / \(ByteFormat.string(swap.totalBytes))"
                             + "   (in: \(swap.swapIns), out: \(swap.swapOuts))")
                lines.append("")
                if snap.compressedUsers.isEmpty {
                    lines.append("Compressed memory per app: none measured"
                                 + (snap.compressedUnreadableCount > 0 ? " (run with sudo to measure more)." : "."))
                } else {
                    lines.append("Compressed memory per app (measured — RAM held by the compressor, swap precursor):")
                    for c in snap.compressedUsers {
                        lines.append("   \(ByteFormat.string(c.compressedBytes))  \(c.appName)  [measured]")
                    }
                    if snap.compressedUnreadableCount > 0 {
                        lines.append("   (\(snap.compressedUnreadableCount) processes could not be measured; run with sudo for fuller coverage)")
                    }
                }
            } else {
                lines.append(statusNote(snap.swapStatus, unreadable: 0))
            }
        }
```

   (No `~` prefix — these are measured, not estimated. No confidence label.)

#### Tests

9. `git mv Tests/MacMemCoreTests/SwapEstimatorTests.swift Tests/MacMemCoreTests/CompressedMemoryAggregatorTests.swift` and replace with measured-semantics tests:

```swift
import XCTest
@testable import MacMemCore

final class CompressedMemoryAggregatorTests: XCTestCase {
    private func group(_ name: String, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: nil, totalFootprintBytes: 0, processCount: pids.count, pids: pids)
    }
    private func sample(_ pid: Int32, compressed: UInt64?) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: nil, name: "p\(pid)",
                      executablePath: nil, footprintBytes: 0, residentBytes: 0,
                      pageIns: 0, compressedBytes: compressed, isReadable: true)
    }

    func testRanksByAggregatedMeasuredCompressed() {
        let groups = [group("Heavy", pids: [1, 2]), group("Light", pids: [3])]
        let samples = [sample(1, compressed: 600), sample(2, compressed: 200), sample(3, compressed: 200)]
        let result = CompressedMemoryAggregator().entries(groups: groups, samples: samples)
        XCTAssertEqual(result.map(\.appName), ["Heavy", "Light"])
        // Measured sum, NOT a proportional share of total swap.
        XCTAssertEqual(result[0].compressedBytes, 800)
        XCTAssertEqual(result[1].compressedBytes, 200)
    }

    func testUnmeasuredProcessesContributeNothing() {
        let groups = [group("A", pids: [1, 2])]
        let samples = [sample(1, compressed: 500), sample(2, compressed: nil)]
        let result = CompressedMemoryAggregator().entries(groups: groups, samples: samples)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].compressedBytes, 500)
    }

    func testGroupsWithZeroCompressedAreExcluded() {
        let result = CompressedMemoryAggregator().entries(
            groups: [group("Z", pids: [1])], samples: [sample(1, compressed: 0)])
        XCTAssertTrue(result.isEmpty)
        let resultNil = CompressedMemoryAggregator().entries(
            groups: [group("Z", pids: [1])], samples: [sample(1, compressed: nil)])
        XCTAssertTrue(resultNil.isEmpty)
    }

    func testNegativeTopNReturnsEmpty() {
        let result = CompressedMemoryAggregator().entries(
            groups: [group("Heavy", pids: [1])], samples: [sample(1, compressed: 600)], topN: -1)
        XCTAssertEqual(result.count, 0)
    }
}
```

10. In `RendererTests.swift`, update the fixture and the swap assertions. Replace the `swapCulprits: [SwapCulprit(...)]` argument with `compressedUsers: [CompressedMemoryEntry(appName: "Brave Browser", bundleID: "com.brave.Browser", compressedBytes: 536_870_912)], compressedUnreadableCount: 3,` and update every other `swap: nil, swapCulprits: [], swapStatus: .ok,` to `swap: nil, compressedUsers: [], swapStatus: .ok,`. Update the assertions that checked `"medium"` and the estimated-swap wording: the row now shows `512.0 MB`, `Brave Browser`, and `[measured]` (not `~`, not `medium`). Add an assertion that the coverage footer appears (`"could not be measured"`). Keep the `testRenderWithNoSwapOmitsSwapSection` test as-is.

11. In `SnapshotBuilderTests.swift`, add a `compressed:` param to the `sample(...)` helper (default `nil`) and thread it into the `ProcessSample(...)` call. Where a test wants to assert measured compressed output, pass `compressed:` on the sample. The `MemorySnapshot` is produced by the builder there (not constructed directly), so no init-rename churn — but any assertion referencing `swapCulprits` must become `compressedUsers`.

#### Steps

- [ ] **Step 1:** Apply the `Models.swift` changes (ProcessSample field w/ default nil, CompressedMemoryEntry replacing SwapCulprit, MemorySnapshot rename + new count).
- [ ] **Step 2:** `git mv` SwapEstimator → CompressedMemoryAggregator and rewrite it; `git mv` the test file and rewrite it.
- [ ] **Step 3:** Run the new aggregator tests, expect FAIL to compile until Models done, then PASS once wired. `swift test --filter CompressedMemoryAggregatorTests`.
- [ ] **Step 4:** Add `compressed(for:)` to NativeMemoryProvider and wire `compressedBytes:` into both ProcessSample constructions.
- [ ] **Step 5:** Update SnapshotBuilder swap section + return.
- [ ] **Step 6:** Update TextRenderer swap block.
- [ ] **Step 7:** Update RendererTests + SnapshotBuilderTests.
- [ ] **Step 8:** `swift build && swift test` — ALL tests green (was 57). Fix any other call sites the rename touched.
- [ ] **Step 9:** Manual sanity (best-effort, may need sudo): `swift run macmem --no-tabs` then `sudo swift run macmem --no-tabs` — confirm the SWAP section prints measured `[measured]` rows and the coverage footer, and that quitting an app removes it from the list on the next run.
- [ ] **Step 10:** Commit:

```bash
git add -A
git commit -m "fix(swap): report measured per-process compressed memory instead of fabricated swap estimate

Replace the page-in proportional-share heuristic (which attributed huge GB
to apps holding no swap and always summed to total swap) with measured
per-process compressed memory via task_info(TASK_VM_INFO).compressed — the
real swap precursor. Keep system swap totals; show [measured] per-app rows
with a coverage footer when task_for_pid is denied (needs sudo).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Constraints:** macOS 13+ target; CLI suggests but never requires sudo; keep each section fault-isolated; do not break the existing apps/tabs sections. Do not touch git branches — stay on `feature/macmem-core-cli`.
