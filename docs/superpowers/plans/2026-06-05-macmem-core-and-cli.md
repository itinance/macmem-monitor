# macmem Core + CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `MacMemCore` (the shared memory-inspection engine) and the `macmem` CLI front-end: top-10 apps by combined footprint, swap total + heuristic culprits, and top browser tabs.

**Architecture:** A UI-free SwiftPM library (`MacMemCore`) acquires data behind a `MemoryProvider` protocol (native `libproc`/`sysctl`/`host_statistics64` by default), computes an immutable `MemorySnapshot` with independent, fault-isolated sections, and exposes pure text/JSON renderers. A thin `swift-argument-parser` executable (`macmem`) builds a snapshot and prints it. All pure logic is unit-tested through fake providers; OS-touching code gets smoke tests.

**Tech Stack:** Swift 5.9+, SwiftPM, swift-argument-parser, Darwin `libproc`/`sysctl`/Mach (`host_statistics64`), `NSWorkspace`/`Bundle` for app identity, `NSAppleScript` for browser tabs. Target macOS 13+.

---

## File Structure

```
macmem/
├── LICENSE                                  # MIT
├── README.md
├── .gitignore
├── Package.swift
├── Sources/
│   ├── MacMemCore/
│   │   ├── Models.swift                      # ProcessSample, AppGroup, SwapInfo, SwapCulprit, BrowserTab, MemorySnapshot, enums
│   │   ├── MemoryProvider.swift             # protocol + FakeMemoryProvider
│   │   ├── NativeMemoryProvider.swift       # libproc + sysctl + host_statistics64
│   │   ├── ResponsiblePID.swift             # private-API wrapper, default-off
│   │   ├── AppGrouper.swift                 # collapse helpers → app, top-N
│   │   ├── SwapEstimator.swift              # culprit ranking
│   │   ├── TabSource.swift                  # protocol + RawTab + FakeTabSource
│   │   ├── AppleScriptTabSource.swift       # NSAppleScript browser bridge
│   │   ├── BrowserInspector.swift           # raw tabs → BrowserTab, count-match estimates
│   │   ├── SnapshotBuilder.swift            # orchestration + fault isolation
│   │   ├── ByteFormat.swift                 # human-readable byte formatting
│   │   ├── TextRenderer.swift               # MemorySnapshot → table string
│   │   └── JSONRenderer.swift               # MemorySnapshot → JSON string
│   └── macmem/
│       └── main.swift                       # ArgumentParser command, wiring, stderr hint
└── Tests/
    └── MacMemCoreTests/
        ├── AppGrouperTests.swift
        ├── SwapEstimatorTests.swift
        ├── BrowserInspectorTests.swift
        ├── SnapshotBuilderTests.swift
        ├── ByteFormatTests.swift
        ├── RendererTests.swift
        └── NativeProviderSmokeTests.swift
```

---

## Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `Sources/MacMemCore/Placeholder.swift` (temporary, removed in Task 2)
- Create: `Sources/macmem/main.swift` (temporary stub)
- Create: `Tests/MacMemCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macmem",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacMemCore", targets: ["MacMemCore"]),
        .executable(name: "macmem", targets: ["macmem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "MacMemCore"),
        .executableTarget(
            name: "macmem",
            dependencies: [
                "MacMemCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MacMemCoreTests", dependencies: ["MacMemCore"]),
    ]
)
```

- [ ] **Step 2: Write MIT `LICENSE`**

```text
MIT License

Copyright (c) 2026 macmem contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write `.gitignore`**

```text
.DS_Store
.build/
DerivedData/
*.xcuserstate
```

- [ ] **Step 4: Write temporary stubs**

`Sources/MacMemCore/Placeholder.swift`:
```swift
public enum MacMemCore {
    public static let version = "0.1.0"
}
```

`Sources/macmem/main.swift`:
```swift
import MacMemCore

print("macmem \(MacMemCore.version)")
```

`Tests/MacMemCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertFalse(MacMemCore.version.isEmpty)
    }
}
```

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; `testVersionExists` PASSES.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold SwiftPM package (MacMemCore + macmem CLI)"
```

---

## Task 2: Domain models

**Files:**
- Create: `Sources/MacMemCore/Models.swift`
- Delete: `Sources/MacMemCore/Placeholder.swift`
- Modify: `Sources/macmem/main.swift` (drop `MacMemCore.version` reference)
- Test: `Tests/MacMemCoreTests/SmokeTests.swift` (replace version test)

- [ ] **Step 1: Write the failing test**

Replace `Tests/MacMemCoreTests/SmokeTests.swift` with:
```swift
import XCTest
@testable import MacMemCore

final class ModelsTests: XCTestCase {
    func testSnapshotIsCodableRoundTrip() throws {
        let snap = MemorySnapshot(
            topApps: [AppGroup(name: "Brave", bundleID: "com.brave.Browser",
                               totalFootprintBytes: 1234, processCount: 3, pids: [1, 2, 3])],
            appsStatus: .ok,
            unreadableProcessCount: 0,
            swap: SwapInfo(totalBytes: 100, usedBytes: 40, freeBytes: 60, swapIns: 5, swapOuts: 2),
            swapCulprits: [SwapCulprit(appName: "Brave", bundleID: "com.brave.Browser",
                                       score: 9.0, confidence: .medium)],
            swapStatus: .ok,
            topTabs: [BrowserTab(browser: "Brave", title: "Example", url: "https://example.com",
                                 estimatedBytes: nil, confidence: .low)],
            tabsStatus: .partial
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelsTests`
Expected: FAIL — `MemorySnapshot` and related types are undefined (compile error).

- [ ] **Step 3: Write `Sources/MacMemCore/Models.swift`**

```swift
import Foundation

public enum Confidence: String, Sendable, Codable, Equatable {
    case high, medium, low
}

public enum SectionStatus: String, Sendable, Codable, Equatable {
    case ok, partial, permissionNeeded, error
}

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
    public let isReadable: Bool

    public init(pid: Int32, ppid: Int32, responsiblePID: Int32?, bundleID: String?,
                name: String, executablePath: String?, footprintBytes: UInt64,
                residentBytes: UInt64, pageIns: UInt64, isReadable: Bool) {
        self.pid = pid; self.ppid = ppid; self.responsiblePID = responsiblePID
        self.bundleID = bundleID; self.name = name; self.executablePath = executablePath
        self.footprintBytes = footprintBytes; self.residentBytes = residentBytes
        self.pageIns = pageIns; self.isReadable = isReadable
    }
}

public struct AppGroup: Sendable, Equatable, Codable {
    public let name: String
    public let bundleID: String?
    public let totalFootprintBytes: UInt64
    public let processCount: Int
    public let pids: [Int32]

    public init(name: String, bundleID: String?, totalFootprintBytes: UInt64,
                processCount: Int, pids: [Int32]) {
        self.name = name; self.bundleID = bundleID
        self.totalFootprintBytes = totalFootprintBytes
        self.processCount = processCount; self.pids = pids
    }
}

public struct SwapInfo: Sendable, Equatable, Codable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    public let swapIns: UInt64
    public let swapOuts: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64,
                swapIns: UInt64, swapOuts: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes; self.freeBytes = freeBytes
        self.swapIns = swapIns; self.swapOuts = swapOuts
    }
}

public struct SwapCulprit: Sendable, Equatable, Codable {
    public let appName: String
    public let bundleID: String?
    public let score: Double
    public let confidence: Confidence

    public init(appName: String, bundleID: String?, score: Double, confidence: Confidence) {
        self.appName = appName; self.bundleID = bundleID
        self.score = score; self.confidence = confidence
    }
}

public struct BrowserTab: Sendable, Equatable, Codable {
    public let browser: String
    public let title: String
    public let url: String
    public let estimatedBytes: UInt64?
    public let confidence: Confidence

    public init(browser: String, title: String, url: String,
                estimatedBytes: UInt64?, confidence: Confidence) {
        self.browser = browser; self.title = title; self.url = url
        self.estimatedBytes = estimatedBytes; self.confidence = confidence
    }
}

public struct MemorySnapshot: Sendable, Equatable, Codable {
    public let topApps: [AppGroup]
    public let appsStatus: SectionStatus
    public let unreadableProcessCount: Int
    public let swap: SwapInfo?
    public let swapCulprits: [SwapCulprit]
    public let swapStatus: SectionStatus
    public let topTabs: [BrowserTab]
    public let tabsStatus: SectionStatus

    public init(topApps: [AppGroup], appsStatus: SectionStatus, unreadableProcessCount: Int,
                swap: SwapInfo?, swapCulprits: [SwapCulprit], swapStatus: SectionStatus,
                topTabs: [BrowserTab], tabsStatus: SectionStatus) {
        self.topApps = topApps; self.appsStatus = appsStatus
        self.unreadableProcessCount = unreadableProcessCount
        self.swap = swap; self.swapCulprits = swapCulprits; self.swapStatus = swapStatus
        self.topTabs = topTabs; self.tabsStatus = tabsStatus
    }
}
```

- [ ] **Step 4: Delete placeholder and fix the stub**

Delete `Sources/MacMemCore/Placeholder.swift`. Replace `Sources/macmem/main.swift` with:
```swift
import MacMemCore

print("macmem (CLI wiring added in Task 11)")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ModelsTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add MacMemCore domain models"
```

---

## Task 3: MemoryProvider protocol + fake

**Files:**
- Create: `Sources/MacMemCore/MemoryProvider.swift`
- Test: `Tests/MacMemCoreTests/AppGrouperTests.swift` (created in Task 4 uses the fake; here add a tiny provider test in a new file)
- Test: `Tests/MacMemCoreTests/ProviderTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/MacMemCoreTests/ProviderTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class ProviderTests: XCTestCase {
    func testFakeProviderReturnsInjectedData() throws {
        let sample = ProcessSample(pid: 1, ppid: 0, responsiblePID: nil, bundleID: nil,
                                   name: "x", executablePath: nil, footprintBytes: 10,
                                   residentBytes: 5, pageIns: 0, isReadable: true)
        let swap = SwapInfo(totalBytes: 1, usedBytes: 0, freeBytes: 1, swapIns: 0, swapOuts: 0)
        let provider = FakeMemoryProvider(processes: [sample], swap: swap)
        XCTAssertEqual(try provider.listProcesses(), [sample])
        XCTAssertEqual(try provider.readSwap(), swap)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderTests`
Expected: FAIL — `MemoryProvider` / `FakeMemoryProvider` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/MemoryProvider.swift`**

```swift
import Foundation

public protocol MemoryProvider: Sendable {
    /// Returns one sample per visible process. Unreadable processes are still
    /// returned with `isReadable == false` and zeroed memory fields.
    func listProcesses() throws -> [ProcessSample]
    func readSwap() throws -> SwapInfo
}

public struct FakeMemoryProvider: MemoryProvider {
    public var processes: [ProcessSample]
    public var swap: SwapInfo
    public var processError: Error?
    public var swapError: Error?

    public init(processes: [ProcessSample], swap: SwapInfo,
                processError: Error? = nil, swapError: Error? = nil) {
        self.processes = processes; self.swap = swap
        self.processError = processError; self.swapError = swapError
    }

    public func listProcesses() throws -> [ProcessSample] {
        if let processError { throw processError }
        return processes
    }
    public func readSwap() throws -> SwapInfo {
        if let swapError { throw swapError }
        return swap
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add MemoryProvider protocol and FakeMemoryProvider"
```

---

## Task 4: AppGrouper (collapse helpers → app)

**Files:**
- Create: `Sources/MacMemCore/AppGrouper.swift`
- Test: `Tests/MacMemCoreTests/AppGrouperTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/MacMemCoreTests/AppGrouperTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class AppGrouperTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        responsible: Int32? = nil) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: responsible, bundleID: bundle,
                      name: name, executablePath: nil, footprintBytes: footprint,
                      residentBytes: footprint, pageIns: 0, isReadable: true)
    }

    func testHelpersCollapseViaBundleSuffixStripping() {
        let samples = [
            sample(1, name: "Brave Browser", bundle: "com.brave.Browser", footprint: 100),
            sample(2, name: "Brave Browser Helper (Renderer)", bundle: "com.brave.Browser.helper.renderer", footprint: 300),
            sample(3, name: "Brave Browser Helper (GPU)", bundle: "com.brave.Browser.helper.gpu", footprint: 50),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "Brave Browser")
        XCTAssertEqual(groups[0].bundleID, "com.brave.Browser")
        XCTAssertEqual(groups[0].totalFootprintBytes, 450)
        XCTAssertEqual(groups[0].processCount, 3)
        XCTAssertEqual(groups[0].pids, [1, 2, 3])
    }

    func testResponsiblePIDOverridesGrouping() {
        let samples = [
            sample(10, name: "Code", bundle: "com.microsoft.VSCode", footprint: 200),
            // Helper with an unrelated bundle but responsible to pid 10:
            sample(11, name: "Code Helper", bundle: nil, footprint: 400, responsible: 10),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "Code")
        XCTAssertEqual(groups[0].totalFootprintBytes, 600)
    }

    func testTopNAndDescendingOrder() {
        let samples = (1...15).map { sample(Int32($0), name: "App\($0)", bundle: "com.x.app\($0)", footprint: UInt64($0)) }
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 10)
        XCTAssertEqual(groups.first?.name, "App15")
        XCTAssertEqual(groups.last?.name, "App6")
    }

    func testResponsiblePIDCycleDoesNotInfiniteLoop() {
        let samples = [
            sample(1, name: "A", bundle: "com.a", footprint: 10, responsible: 2),
            sample(2, name: "B", bundle: "com.b", footprint: 10, responsible: 1),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.reduce(0) { $0 + Int($1.totalFootprintBytes) }, 20)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppGrouperTests`
Expected: FAIL — `AppGrouper` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/AppGrouper.swift`**

```swift
import Foundation

/// Collapses helper/renderer processes into their owning application.
///
/// Strategy (layered): the *preferred* signal is the responsible PID
/// (see `ResponsiblePID.swift` — a private API, default-off). The always-available
/// public fallback groups by base bundle identifier (helper suffixes stripped),
/// then by cleaned process name.
public struct AppGrouper {
    public init() {}

    public func group(_ samples: [ProcessSample], topN: Int = 10) -> [AppGroup] {
        let byPID = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        struct Acc { var name: String; var bundleID: String?; var total: UInt64; var pids: [Int32] }
        var groups: [String: Acc] = [:]

        for s in samples {
            let owner = resolveOwner(s, byPID: byPID, depth: 0)
            let key = owner.bundleID ?? owner.name
            if var acc = groups[key] {
                acc.total += s.footprintBytes
                acc.pids.append(s.pid)
                groups[key] = acc
            } else {
                groups[key] = Acc(name: owner.name, bundleID: owner.bundleID,
                                  total: s.footprintBytes, pids: [s.pid])
            }
        }

        return groups.values
            .map { AppGroup(name: $0.name, bundleID: $0.bundleID,
                            totalFootprintBytes: $0.total,
                            processCount: $0.pids.count, pids: $0.pids.sorted()) }
            .sorted { $0.totalFootprintBytes > $1.totalFootprintBytes }
            .prefix(topN)
            .map { $0 }
    }

    func resolveOwner(_ s: ProcessSample, byPID: [Int32: ProcessSample],
                      depth: Int) -> (name: String, bundleID: String?) {
        if depth < 8, let rpid = s.responsiblePID, rpid != s.pid, let owner = byPID[rpid] {
            return resolveOwner(owner, byPID: byPID, depth: depth + 1)
        }
        return (Self.cleanName(s.name), s.bundleID.map(Self.baseBundleID))
    }

    static func baseBundleID(_ id: String) -> String {
        let suffixes = [".helper.renderer", ".helper.gpu", ".helper.plugin", ".helper"]
        for suffix in suffixes where id.lowercased().hasSuffix(suffix) {
            return String(id.dropLast(suffix.count))
        }
        return id
    }

    static func cleanName(_ name: String) -> String {
        if let range = name.range(of: " Helper") {
            return String(name[..<range.lowerBound])
        }
        return name
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppGrouperTests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AppGrouper with bundle-suffix + responsible-PID grouping"
```

---

## Task 5: SwapEstimator (culprit ranking)

**Files:**
- Create: `Sources/MacMemCore/SwapEstimator.swift`
- Test: `Tests/MacMemCoreTests/SwapEstimatorTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/MacMemCoreTests/SwapEstimatorTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class SwapEstimatorTests: XCTestCase {
    private func group(_ name: String, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: nil, totalFootprintBytes: 0, processCount: pids.count, pids: pids)
    }
    private func sample(_ pid: Int32, pageIns: UInt64) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: nil, name: "p\(pid)",
                      executablePath: nil, footprintBytes: 0, residentBytes: 0,
                      pageIns: pageIns, isReadable: true)
    }

    func testNoCulpritsWhenSwapUnused() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 0, freeBytes: 100, swapIns: 0, swapOuts: 0)
        let result = SwapEstimator().culprits(groups: [group("A", pids: [1])],
                                              samples: [sample(1, pageIns: 999)], swap: swap)
        XCTAssertTrue(result.isEmpty)
    }

    func testRanksByAggregatedPageInsWithConfidence() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 80, freeBytes: 20, swapIns: 10, swapOuts: 5)
        let groups = [group("Heavy", pids: [1, 2]), group("Light", pids: [3])]
        let samples = [sample(1, pageIns: 600), sample(2, pageIns: 200), sample(3, pageIns: 200)]
        let result = SwapEstimator().culprits(groups: groups, samples: samples, swap: swap)
        XCTAssertEqual(result.map(\.appName), ["Heavy", "Light"])
        XCTAssertEqual(result[0].score, 800)
        XCTAssertEqual(result[0].confidence, .high)   // 800/1000 = 0.8 > 0.5
        XCTAssertEqual(result[1].confidence, .low)    // 200/1000 = 0.2, not > 0.2
    }

    func testGroupsWithZeroPageInsAreExcluded() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 50, freeBytes: 50, swapIns: 1, swapOuts: 1)
        let result = SwapEstimator().culprits(groups: [group("Z", pids: [1])],
                                              samples: [sample(1, pageIns: 0)], swap: swap)
        XCTAssertTrue(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SwapEstimatorTests`
Expected: FAIL — `SwapEstimator` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/SwapEstimator.swift`**

```swift
import Foundation

/// Ranks likely swap contributors. NOTE: `pageIns` is a *noisy* proxy — it
/// counts file + anonymous page-ins, not swap-ins specifically. The whole
/// section is therefore an estimate and is always confidence-labeled.
public struct SwapEstimator {
    public init() {}

    public func culprits(groups: [AppGroup], samples: [ProcessSample],
                         swap: SwapInfo, topN: Int = 10) -> [SwapCulprit] {
        guard swap.usedBytes > 0 else { return [] }

        let pageInsByPID = Dictionary(samples.map { ($0.pid, $0.pageIns) },
                                      uniquingKeysWith: { a, _ in a })
        let scored: [(group: AppGroup, score: Double)] = groups.compactMap { g in
            let total = g.pids.reduce(0.0) { $0 + Double(pageInsByPID[$1] ?? 0) }
            return total > 0 ? (g, total) : nil
        }
        let grandTotal = scored.reduce(0.0) { $0 + $1.score }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(topN)
            .map { entry in
                let share = grandTotal > 0 ? entry.score / grandTotal : 0
                let confidence: Confidence = share > 0.5 ? .high : (share > 0.2 ? .medium : .low)
                return SwapCulprit(appName: entry.group.name, bundleID: entry.group.bundleID,
                                   score: entry.score, confidence: confidence)
            }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SwapEstimatorTests`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SwapEstimator culprit ranking"
```

---

## Task 6: TabSource protocol + BrowserInspector

**Files:**
- Create: `Sources/MacMemCore/TabSource.swift`
- Create: `Sources/MacMemCore/BrowserInspector.swift`
- Test: `Tests/MacMemCoreTests/BrowserInspectorTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/MacMemCoreTests/BrowserInspectorTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class BrowserInspectorTests: XCTestCase {
    func testListsTabsWithoutEstimatesWhenNoRendererData() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        let tabs = try BrowserInspector(source: source).topTabs(rendererFootprintsByBrowser: [:], topN: 10)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertTrue(tabs.allSatisfy { $0.estimatedBytes == nil })
        XCTAssertTrue(tabs.allSatisfy { $0.confidence == .low })
    }

    func testCountMatchEnablesEstimatesAndHeaviestOrdering() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        // Two renderers, footprints 500 and 100 -> heaviest tab gets 500.
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: ["Brave": [100, 500]], topN: 10)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].estimatedBytes, 500)
        XCTAssertEqual(tabs[1].estimatedBytes, 100)
    }

    func testCountMismatchLeavesEstimatesBlank() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: ["Brave": [500]], topN: 10)  // 1 renderer, 2 tabs
        XCTAssertTrue(tabs.allSatisfy { $0.estimatedBytes == nil })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BrowserInspectorTests`
Expected: FAIL — `TabSource` / `RawTab` / `FakeTabSource` / `BrowserInspector` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/TabSource.swift`**

```swift
import Foundation

public struct RawTab: Sendable, Equatable {
    public let title: String
    public let url: String
    public let windowIndex: Int
    public let tabIndex: Int
    public init(title: String, url: String, windowIndex: Int, tabIndex: Int) {
        self.title = title; self.url = url
        self.windowIndex = windowIndex; self.tabIndex = tabIndex
    }
}

public protocol TabSource: Sendable {
    /// Display names of browsers currently running and inspectable.
    func runningBrowsers() -> [String]
    func tabs(for browser: String) throws -> [RawTab]
}

public struct FakeTabSource: TabSource {
    public var byBrowser: [String: [RawTab]]
    public var errorsByBrowser: [String: Error]
    public init(byBrowser: [String: [RawTab]], errorsByBrowser: [String: Error] = [:]) {
        self.byBrowser = byBrowser; self.errorsByBrowser = errorsByBrowser
    }
    public func runningBrowsers() -> [String] { byBrowser.keys.sorted() }
    public func tabs(for browser: String) throws -> [RawTab] {
        if let e = errorsByBrowser[browser] { throw e }
        return byBrowser[browser] ?? []
    }
}
```

- [ ] **Step 4: Write `Sources/MacMemCore/BrowserInspector.swift`**

```swift
import Foundation

/// Turns raw browser tabs into `BrowserTab`s. Per-tab memory is a heuristic:
/// when a browser's renderer-process count equals its tab count, we pair
/// renderer footprints (largest → largest) to tabs. Any mismatch leaves the
/// estimate blank, per the spec's "leave blank when ambiguous" rule.
public struct BrowserInspector {
    let source: TabSource
    public init(source: TabSource) { self.source = source }

    public func topTabs(rendererFootprintsByBrowser: [String: [UInt64]] = [:],
                        topN: Int = 10) throws -> [BrowserTab] {
        var all: [BrowserTab] = []

        for browser in source.runningBrowsers() {
            let raw = try source.tabs(for: browser)
            let footprints = rendererFootprintsByBrowser[browser] ?? []

            if footprints.count == raw.count, !raw.isEmpty {
                let sortedFootprints = footprints.sorted(by: >)
                for (tab, bytes) in zip(raw, sortedFootprints) {
                    all.append(BrowserTab(browser: browser, title: tab.title, url: tab.url,
                                          estimatedBytes: bytes, confidence: .low))
                }
            } else {
                for tab in raw {
                    all.append(BrowserTab(browser: browser, title: tab.title, url: tab.url,
                                          estimatedBytes: nil, confidence: .low))
                }
            }
        }

        // Heaviest first when estimates exist; tabs without estimates sort last.
        return all
            .sorted { ($0.estimatedBytes ?? 0) > ($1.estimatedBytes ?? 0) }
            .prefix(topN)
            .map { $0 }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter BrowserInspectorTests`
Expected: PASS (all three).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add TabSource protocol and BrowserInspector heuristic estimates"
```

---

## Task 7: SnapshotBuilder (orchestration + fault isolation)

**Files:**
- Create: `Sources/MacMemCore/SnapshotBuilder.swift`
- Test: `Tests/MacMemCoreTests/SnapshotBuilderTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/MacMemCoreTests/SnapshotBuilderTests.swift`:
```swift
import XCTest
@testable import MacMemCore

private struct DummyError: Error {}

final class SnapshotBuilderTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        pageIns: UInt64 = 0, readable: Bool = true) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: bundle, name: name,
                      executablePath: nil, footprintBytes: footprint, residentBytes: footprint,
                      pageIns: pageIns, isReadable: readable)
    }

    func testBuildsAllSectionsOK() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "Brave Browser", bundle: "com.brave.Browser", footprint: 100, pageIns: 50)],
            swap: SwapInfo(totalBytes: 100, usedBytes: 40, freeBytes: 60, swapIns: 3, swapOuts: 1))
        let tabSource = FakeTabSource(byBrowser: [
            "Brave Browser": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)]])
        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: 10)

        XCTAssertEqual(snap.appsStatus, .ok)
        XCTAssertEqual(snap.topApps.first?.name, "Brave Browser")
        XCTAssertEqual(snap.swapStatus, .ok)
        XCTAssertEqual(snap.swap?.usedBytes, 40)
        XCTAssertEqual(snap.tabsStatus, .ok)
        XCTAssertEqual(snap.topTabs.first?.url, "https://a.com")
        XCTAssertEqual(snap.unreadableProcessCount, 0)
    }

    func testUnreadableProcessesAreCounted() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "A", bundle: "com.a", footprint: 10),
                        sample(2, name: "root", bundle: nil, footprint: 0, readable: false)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build()
        XCTAssertEqual(snap.unreadableProcessCount, 1)
    }

    func testProviderFailureYieldsErrorStatusNotCrash() {
        let provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0),
            processError: DummyError())
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build()
        XCTAssertEqual(snap.appsStatus, .error)
        XCTAssertTrue(snap.topApps.isEmpty)
    }

    func testTabSourceFailureYieldsPartialTabs() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "A", bundle: "com.a", footprint: 10)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let tabSource = FakeTabSource(byBrowser: ["Brave Browser": []],
                                      errorsByBrowser: ["Brave Browser": DummyError()])
        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build()
        XCTAssertEqual(snap.tabsStatus, .partial)
    }

    func testNilTabSourceMarksTabsPermissionNeeded() {
        let provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build()
        XCTAssertEqual(snap.tabsStatus, .permissionNeeded)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SnapshotBuilderTests`
Expected: FAIL — `SnapshotBuilder` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/SnapshotBuilder.swift`**

```swift
import Foundation

/// Orchestrates provider + grouper + estimator + inspector into one snapshot.
/// Each section is computed independently inside its own do/catch so a failure
/// in one never fails the others.
public struct SnapshotBuilder {
    let provider: MemoryProvider
    let tabSource: TabSource?
    let knownBrowsers: Set<String>

    public init(provider: MemoryProvider, tabSource: TabSource?,
                knownBrowsers: Set<String> = ["Brave Browser", "Google Chrome", "Microsoft Edge", "Safari"]) {
        self.provider = provider
        self.tabSource = tabSource
        self.knownBrowsers = knownBrowsers
    }

    public func build(topN: Int = 10, includeTabs: Bool = true, includeSwap: Bool = true) -> MemorySnapshot {
        // --- Apps section ---
        var topApps: [AppGroup] = []
        var appsStatus: SectionStatus = .ok
        var unreadable = 0
        var samples: [ProcessSample] = []
        do {
            samples = try provider.listProcesses()
            unreadable = samples.filter { !$0.isReadable }.count
            topApps = AppGrouper().group(samples.filter { $0.isReadable }, topN: topN)
            appsStatus = unreadable > 0 ? .partial : .ok
        } catch {
            appsStatus = .error
        }

        // --- Swap section ---
        var swap: SwapInfo?
        var culprits: [SwapCulprit] = []
        var swapStatus: SectionStatus = .ok
        if includeSwap {
            do {
                let info = try provider.readSwap()
                swap = info
                let groups = AppGrouper().group(samples.filter { $0.isReadable }, topN: topN)
                culprits = SwapEstimator().culprits(groups: groups, samples: samples, swap: info, topN: topN)
            } catch {
                swapStatus = .error
            }
        } else {
            swapStatus = .ok
        }

        // --- Tabs section ---
        var topTabs: [BrowserTab] = []
        var tabsStatus: SectionStatus = .ok
        if includeTabs {
            if let tabSource {
                do {
                    let footprints = rendererFootprints(from: samples, topApps: topApps)
                    topTabs = try BrowserInspector(source: tabSource)
                        .topTabs(rendererFootprintsByBrowser: footprints, topN: topN)
                    tabsStatus = .ok
                } catch {
                    tabsStatus = .partial
                }
            } else {
                tabsStatus = .permissionNeeded
            }
        }

        return MemorySnapshot(topApps: topApps, appsStatus: appsStatus,
                              unreadableProcessCount: unreadable, swap: swap,
                              swapCulprits: culprits, swapStatus: swapStatus,
                              topTabs: topTabs, tabsStatus: tabsStatus)
    }

    /// Renderer footprints per browser, keyed by the browser's display name.
    /// A "renderer" is a helper process whose owning group is a known browser.
    func rendererFootprints(from samples: [ProcessSample], topApps: [AppGroup]) -> [String: [UInt64]] {
        var result: [String: [UInt64]] = [:]
        let pidToFootprint = Dictionary(samples.map { ($0.pid, $0.footprintBytes) },
                                        uniquingKeysWith: { a, _ in a })
        for group in topApps where knownBrowsers.contains(group.name) {
            let footprints = group.pids.compactMap { pidToFootprint[$0] }
            result[group.name] = footprints
        }
        return result
    }
}
```

Note: this maps *all* of a browser's process footprints (not only renderers) to tabs; the count-match guard in `BrowserInspector` keeps that honest by refusing to estimate unless counts line up. Refining "which pids are renderers" is a documented follow-up.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SnapshotBuilderTests`
Expected: PASS (all five).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SnapshotBuilder with per-section fault isolation"
```

---

## Task 8: ByteFormat + renderers (text & JSON)

**Files:**
- Create: `Sources/MacMemCore/ByteFormat.swift`
- Create: `Sources/MacMemCore/TextRenderer.swift`
- Create: `Sources/MacMemCore/JSONRenderer.swift`
- Test: `Tests/MacMemCoreTests/ByteFormatTests.swift`
- Test: `Tests/MacMemCoreTests/RendererTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/MacMemCoreTests/ByteFormatTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class ByteFormatTests: XCTestCase {
    func testFormatsBinaryUnits() {
        XCTAssertEqual(ByteFormat.string(512), "512 B")
        XCTAssertEqual(ByteFormat.string(1024), "1.0 KB")
        XCTAssertEqual(ByteFormat.string(1_572_864), "1.5 MB")
        XCTAssertEqual(ByteFormat.string(2_147_483_648), "2.0 GB")
    }
}
```

`Tests/MacMemCoreTests/RendererTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class RendererTests: XCTestCase {
    private func fixture() -> MemorySnapshot {
        MemorySnapshot(
            topApps: [AppGroup(name: "Brave Browser", bundleID: "com.brave.Browser",
                               totalFootprintBytes: 1_572_864, processCount: 3, pids: [1, 2, 3])],
            appsStatus: .ok, unreadableProcessCount: 0,
            swap: SwapInfo(totalBytes: 2_147_483_648, usedBytes: 1_073_741_824,
                           freeBytes: 1_073_741_824, swapIns: 10, swapOuts: 4),
            swapCulprits: [SwapCulprit(appName: "Brave Browser", bundleID: "com.brave.Browser",
                                       score: 100, confidence: .medium)],
            swapStatus: .ok,
            topTabs: [BrowserTab(browser: "Brave Browser", title: "Example",
                                 url: "https://example.com", estimatedBytes: 1_048_576, confidence: .low)],
            tabsStatus: .ok)
    }

    func testTextRendererContainsAllSections() {
        let out = TextRenderer.render(fixture())
        XCTAssertTrue(out.contains("TOP APPS"))
        XCTAssertTrue(out.contains("Brave Browser"))
        XCTAssertTrue(out.contains("1.5 MB"))
        XCTAssertTrue(out.contains("SWAP"))
        XCTAssertTrue(out.contains("1.0 GB"))
        XCTAssertTrue(out.contains("BROWSER TABS"))
        XCTAssertTrue(out.contains("https://example.com"))
        XCTAssertTrue(out.contains("~"))               // estimate marker
        XCTAssertTrue(out.contains("medium"))          // culprit confidence
    }

    func testJSONRendererIsValidAndRoundTrips() throws {
        let json = try JSONRenderer.render(fixture())
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, fixture())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ByteFormatTests` then `swift test --filter RendererTests`
Expected: FAIL — `ByteFormat`, `TextRenderer`, `JSONRenderer` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/ByteFormat.swift`**

```swift
import Foundation

public enum ByteFormat {
    /// Binary (1024-based) human-readable size, e.g. "1.5 MB".
    public static func string(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[unit])
    }
}
```

- [ ] **Step 4: Write `Sources/MacMemCore/TextRenderer.swift`**

```swift
import Foundation

public enum TextRenderer {
    public static func render(_ snap: MemorySnapshot) -> String {
        var lines: [String] = []

        lines.append("== TOP APPS (by combined memory) ==")
        lines.append(statusNote(snap.appsStatus, unreadable: snap.unreadableProcessCount))
        for (i, app) in snap.topApps.enumerated() {
            lines.append(String(format: "%2d. %-28@  %10@  (%d proc)",
                                i + 1, app.name as NSString,
                                ByteFormat.string(app.totalFootprintBytes) as NSString,
                                app.processCount))
        }

        lines.append("")
        lines.append("== SWAP ==")
        if let swap = snap.swap {
            lines.append("Used \(ByteFormat.string(swap.usedBytes)) / \(ByteFormat.string(swap.totalBytes))"
                         + "   (in: \(swap.swapIns), out: \(swap.swapOuts))")
            if snap.swapCulprits.isEmpty {
                lines.append("No swap in use, or no estimable culprits.")
            } else {
                lines.append("Likely contributors (estimates):")
                for c in snap.swapCulprits {
                    lines.append("   ~ \(c.appName)  [\(c.confidence.rawValue)]")
                }
            }
        } else {
            lines.append(statusNote(snap.swapStatus, unreadable: 0))
        }

        lines.append("")
        lines.append("== BROWSER TABS (heaviest) ==")
        if snap.topTabs.isEmpty {
            lines.append(statusNote(snap.tabsStatus, unreadable: 0))
        } else {
            for (i, tab) in snap.topTabs.enumerated() {
                let mem = tab.estimatedBytes.map { "~\(ByteFormat.string($0))" } ?? "  (n/a)"
                lines.append(String(format: "%2d. %10@  %@", i + 1, mem as NSString, tab.url as NSString))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func statusNote(_ status: SectionStatus, unreadable: Int) -> String {
        switch status {
        case .ok: return unreadable > 0 ? "(\(unreadable) processes not readable)" : ""
        case .partial: return "(partial — \(unreadable) processes not readable; run with sudo for full coverage)"
        case .permissionNeeded: return "(permission needed — grant Automation access to read browser tabs)"
        case .error: return "(unavailable — failed to read this section)"
        }
    }
}
```

- [ ] **Step 5: Write `Sources/MacMemCore/JSONRenderer.swift`**

```swift
import Foundation

public enum JSONRenderer {
    public static func render(_ snap: MemorySnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snap)
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ByteFormatTests` then `swift test --filter RendererTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add ByteFormat and text/JSON renderers"
```

---

## Task 9: NativeMemoryProvider (libproc + sysctl + Mach)

**Files:**
- Create: `Sources/MacMemCore/NativeMemoryProvider.swift`
- Test: `Tests/MacMemCoreTests/NativeProviderSmokeTests.swift`

This task touches real OS APIs, so it's verified with a smoke test against the test process itself rather than fabricated equality assertions.

- [ ] **Step 1: Write the failing smoke test**

`Tests/MacMemCoreTests/NativeProviderSmokeTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class NativeProviderSmokeTests: XCTestCase {
    func testListsProcessesIncludingSelfWithFootprint() throws {
        let provider = NativeMemoryProvider()
        let processes = try provider.listProcesses()
        XCTAssertFalse(processes.isEmpty)

        let me = ProcessInfo.processInfo.processIdentifier
        guard let mine = processes.first(where: { $0.pid == me }) else {
            return XCTFail("current process not found in list")
        }
        XCTAssertTrue(mine.isReadable)
        XCTAssertGreaterThan(mine.footprintBytes, 0)
        XCTAssertFalse(mine.name.isEmpty)
    }

    func testReadsSwapTotals() throws {
        let swap = try NativeMemoryProvider().readSwap()
        // total >= used; counters are non-negative by type. Just assert it returns.
        XCTAssertGreaterThanOrEqual(swap.totalBytes, swap.usedBytes)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NativeProviderSmokeTests`
Expected: FAIL — `NativeMemoryProvider` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/NativeMemoryProvider.swift`**

```swift
import Foundation
import Darwin

public struct NativeMemoryProvider: MemoryProvider {
    public init() {}

    // MARK: Processes

    public func listProcesses() throws -> [ProcessSample] {
        let pids = try allPIDs()
        let appIdentity = Self.appIdentityByPID()   // bundleID + name for GUI apps

        return pids.compactMap { pid -> ProcessSample? in
            guard pid > 0 else { return nil }
            let path = Self.path(for: pid)
            let bsd = Self.bsdInfo(for: pid)
            let name = appIdentity[pid]?.name ?? Self.name(for: pid, fallbackPath: path)
            let bundleID = appIdentity[pid]?.bundleID ?? Self.bundleID(forPath: path)

            if let usage = Self.rusage(for: pid) {
                return ProcessSample(pid: pid, ppid: bsd.ppid, responsiblePID: nil,
                                     bundleID: bundleID, name: name, executablePath: path,
                                     footprintBytes: usage.footprint, residentBytes: usage.resident,
                                     pageIns: usage.pageIns, isReadable: true)
            } else {
                // Not owned by us / not permitted: still list it, marked unreadable.
                return ProcessSample(pid: pid, ppid: bsd.ppid, responsiblePID: nil,
                                     bundleID: bundleID, name: name, executablePath: path,
                                     footprintBytes: 0, residentBytes: 0, pageIns: 0, isReadable: false)
            }
        }
    }

    private func allPIDs() throws -> [pid_t] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { throw NativeError.procListFailed }
        let count = Int(needed) / MemoryLayout<pid_t>.size
        var buffer = [pid_t](repeating: 0, count: count)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, needed)
        guard written > 0 else { throw NativeError.procListFailed }
        let actual = Int(written) / MemoryLayout<pid_t>.size
        return Array(buffer.prefix(actual)).filter { $0 != 0 }
    }

    private static func rusage(for pid: pid_t) -> (footprint: UInt64, resident: UInt64, pageIns: UInt64)? {
        var info = rusage_info_v2()
        let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, reboundPtr)
            }
        }
        guard rc == 0 else { return nil }
        return (info.ri_phys_footprint, info.ri_resident_size, info.ri_pageins)
    }

    private static func bsdInfo(for pid: pid_t) -> (ppid: Int32, isApp: Bool) {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard rc == size else { return (0, false) }
        return (Int32(info.pbi_ppid), false)
    }

    private static func path(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
        let rc = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return rc > 0 ? String(cString: buffer) : nil
    }

    private static func name(for pid: pid_t, fallbackPath: String?) -> String {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN))
        let rc = proc_name(pid, &buffer, UInt32(buffer.count))
        if rc > 0 { return String(cString: buffer) }
        if let p = fallbackPath { return (p as NSString).lastPathComponent }
        return "pid \(pid)"
    }

    private static func bundleID(forPath path: String?) -> String? {
        guard let path else { return nil }
        // Walk up to the enclosing .app, read its Info.plist bundle id.
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return Bundle(url: url)?.bundleIdentifier
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// Map of pid → (bundleID, localizedName) for GUI applications via NSWorkspace.
    private static func appIdentityByPID() -> [pid_t: (bundleID: String?, name: String)] {
        var map: [pid_t: (String?, String)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            map[pid] = (app.bundleIdentifier, app.localizedName ?? "pid \(pid)")
        }
        return map
    }

    // MARK: Swap

    public func readSwap() throws -> SwapInfo {
        let usage = try Self.swapUsage()
        let (ins, outs) = Self.swapInOut()
        return SwapInfo(totalBytes: usage.total, usedBytes: usage.used,
                        freeBytes: usage.avail, swapIns: ins, swapOuts: outs)
    }

    private static func swapUsage() throws -> (total: UInt64, used: UInt64, avail: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib = [CTL_VM, VM_SWAPUSAGE]
        let rc = sysctl(&mib, 2, &usage, &size, nil, 0)
        guard rc == 0 else { throw NativeError.sysctlFailed }
        return (usage.xsu_total, usage.xsu_used, usage.xsu_avail)
    }

    private static func swapInOut() -> (ins: UInt64, outs: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let rc = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard rc == KERN_SUCCESS else { return (0, 0) }
        return (UInt64(stats.swapins), UInt64(stats.swapouts))
    }
}

enum NativeError: Error {
    case procListFailed
    case sysctlFailed
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NativeProviderSmokeTests`
Expected: PASS. If `rusage_info_t?` rebinding fails to compile on the toolchain, change the `withMemoryRebound(to: rusage_info_t?.self ...)` line to `withMemoryRebound(to: rusage_info_t.self ...)` (drop the optional) — both forms appear across SDK versions; pick the one that compiles.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add NativeMemoryProvider (libproc + sysctl + host_statistics64)"
```

---

## Task 10: ResponsiblePID private-API wrapper (default-off)

**Files:**
- Create: `Sources/MacMemCore/ResponsiblePID.swift`
- Modify: `Sources/MacMemCore/NativeMemoryProvider.swift` (opt-in flag)
- Test: `Tests/MacMemCoreTests/ResponsiblePIDTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/MacMemCoreTests/ResponsiblePIDTests.swift`:
```swift
import XCTest
@testable import MacMemCore

final class ResponsiblePIDTests: XCTestCase {
    func testDisabledByDefaultReturnsNil() {
        XCTAssertNil(ResponsiblePID.lookup(for: ProcessInfo.processInfo.processIdentifier, enabled: false))
    }

    func testEnabledReturnsSelfForOwnProcess() {
        let me = ProcessInfo.processInfo.processIdentifier
        let r = ResponsiblePID.lookup(for: me, enabled: true)
        // The responsible pid for our own (non-helper) process is itself.
        XCTAssertEqual(r, me)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ResponsiblePIDTests`
Expected: FAIL — `ResponsiblePID` undefined.

- [ ] **Step 3: Write `Sources/MacMemCore/ResponsiblePID.swift`**

```swift
import Foundation

/// Wrapper around the PRIVATE/undocumented libsystem symbol
/// `responsibility_get_pid_responsible_for_pid`. There is NO public API for
/// this. It improves helper→app grouping but is a notarization/OS-break risk,
/// so it is DEFAULT-OFF and isolated to this one file. Disable or delete this
/// file and grouping still works via the public bundle-ID/name fallback.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

public enum ResponsiblePID {
    public static func lookup(for pid: pid_t, enabled: Bool) -> pid_t? {
        guard enabled else { return nil }
        let result = responsibility_get_pid_responsible_for_pid(pid)
        return result > 0 ? result : nil
    }
}
```

- [ ] **Step 4: Wire the opt-in flag into NativeMemoryProvider**

In `Sources/MacMemCore/NativeMemoryProvider.swift`, change the struct to accept the flag and populate `responsiblePID`:

Replace:
```swift
public struct NativeMemoryProvider: MemoryProvider {
    public init() {}
```
with:
```swift
public struct NativeMemoryProvider: MemoryProvider {
    public let useResponsiblePID: Bool
    public init(useResponsiblePID: Bool = false) {
        self.useResponsiblePID = useResponsiblePID
    }
```

Then in `listProcesses()`, replace both `responsiblePID: nil` occurrences with:
```swift
responsiblePID: ResponsiblePID.lookup(for: pid, enabled: useResponsiblePID),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ResponsiblePIDTests` then `swift test`
Expected: PASS. (If the private symbol is unavailable at link time on a future OS, this is the single file to disable.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add default-off responsible-PID private-API wrapper"
```

---

## Task 11: CLI command wiring

**Files:**
- Modify: `Sources/macmem/main.swift`

- [ ] **Step 1: Write `Sources/macmem/main.swift`**

```swift
import ArgumentParser
import Darwin
import Foundation
import MacMemCore

struct Macmem: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macmem",
        abstract: "Show the heaviest apps, swap usage, and browser tabs on macOS."
    )

    @Option(name: .shortAndLong, help: "How many items per section.")
    var top: Int = 10

    @Flag(name: .long, help: "Emit JSON instead of a table.")
    var json = false

    @Flag(name: .long, help: "Skip the browser tabs section.")
    var noTabs = false

    @Flag(name: .long, help: "Skip the swap section.")
    var noSwap = false

    @Option(name: .long, help: "Repeat every N seconds (live view).")
    var watch: Double?

    @Flag(name: .long, help: "Use the private responsible-PID API for better grouping (off by default).")
    var responsiblePid = false

    func run() throws {
        if let interval = watch {
            while true {
                printOnce(clear: true)
                Thread.sleep(forTimeInterval: max(0.5, interval))
            }
        } else {
            printOnce(clear: false)
        }
    }

    private func printOnce(clear: Bool) {
        if clear { print("\u{001B}[2J\u{001B}[H", terminator: "") }

        let provider = NativeMemoryProvider(useResponsiblePID: responsiblePid)
        let tabSource: TabSource? = noTabs ? nil : AppleScriptTabSource()
        let snapshot = SnapshotBuilder(provider: provider, tabSource: tabSource)
            .build(topN: top, includeTabs: !noTabs, includeSwap: !noSwap)

        if json {
            if let out = try? JSONRenderer.render(snapshot) { print(out) }
        } else {
            print(TextRenderer.render(snapshot))
        }

        printPrivilegeHintIfNeeded(snapshot)
    }

    private func printPrivilegeHintIfNeeded(_ snapshot: MemorySnapshot) {
        if geteuid() != 0 && snapshot.unreadableProcessCount > 0 {
            FileHandle.standardError.write(Data(
                "\n\(snapshot.unreadableProcessCount) processes not readable — run `sudo macmem` for full coverage.\n".utf8))
        }
    }
}

Macmem.main()
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds. (Depends on `AppleScriptTabSource` from Task 12 — if building before Task 12, temporarily pass `nil` for `tabSource`. Implement Task 12 next so this compiles fully.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: wire macmem CLI command (flags, watch, json, privilege hint)"
```

---

## Task 12: AppleScriptTabSource (live browser bridge)

**Files:**
- Create: `Sources/MacMemCore/AppleScriptTabSource.swift`
- Test: manual (live, requires Automation permission) — no XCTest, since it triggers a TCC prompt

- [ ] **Step 1: Write `Sources/MacMemCore/AppleScriptTabSource.swift`**

```swift
import Foundation

/// Reads browser tabs via AppleScript. Triggers a one-time macOS Automation
/// (TCC) prompt per browser. On denial/error, throws so SnapshotBuilder marks
/// the tabs section `.partial`.
public struct AppleScriptTabSource: TabSource {
    private let candidates: [String]
    public init(candidates: [String] = ["Brave Browser", "Google Chrome", "Microsoft Edge", "Safari"]) {
        self.candidates = candidates
    }

    public func runningBrowsers() -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })
        return candidates.filter { running.contains($0) }
    }

    public func tabs(for browser: String) throws -> [RawTab] {
        let script = browser == "Safari" ? Self.safariScript : Self.chromiumScript(app: browser)
        let output = try runAppleScript(script)
        return Self.parse(output)
    }

    // Output format: one tab per line as "windowIndex\ttabIndex\tURL\tTITLE"
    private static func chromiumScript(app: String) -> String {
        """
        set out to ""
        tell application "\(app)"
            set wi to 0
            repeat with w in windows
                set ti to 0
                repeat with t in tabs of w
                    set out to out & wi & tab & ti & tab & (URL of t) & tab & (title of t) & linefeed
                    set ti to ti + 1
                end repeat
                set wi to wi + 1
            end repeat
        end tell
        return out
        """
    }

    private static let safariScript = """
        set out to ""
        tell application "Safari"
            set wi to 0
            repeat with w in windows
                set ti to 0
                repeat with t in tabs of w
                    set out to out & wi & tab & ti & tab & (URL of t) & tab & (name of t) & linefeed
                    set ti to ti + 1
                end repeat
                set wi to wi + 1
            end repeat
        end tell
        return out
        """

    private func runAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw TabError.compileFailed }
        let result = script.executeAndReturnError(&error)
        if let error { throw TabError.execFailed(String(describing: error)) }
        return result.stringValue ?? ""
    }

    static func parse(_ raw: String) -> [RawTab] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4,
                  let wi = Int(parts[0]), let ti = Int(parts[1]) else { return nil }
            let url = parts[2]
            let title = parts[3...].joined(separator: "\t")
            guard !url.isEmpty else { return nil }
            return RawTab(title: title, url: url, windowIndex: wi, tabIndex: ti)
        }
    }
}

enum TabError: Error {
    case compileFailed
    case execFailed(String)
}
```

- [ ] **Step 2: Add a parser unit test** (parsing is pure and testable without TCC)

Append to `Tests/MacMemCoreTests/BrowserInspectorTests.swift`:
```swift
extension BrowserInspectorTests {
    func testAppleScriptOutputParsing() {
        let raw = "0\t0\thttps://a.com\tAlpha\n0\t1\thttps://b.com\tBeta\textra\n0\t2\t\tEmptyURL\n"
        let tabs = AppleScriptTabSource.parse(raw)
        XCTAssertEqual(tabs.count, 2)                       // empty-URL line dropped
        XCTAssertEqual(tabs[0].url, "https://a.com")
        XCTAssertEqual(tabs[0].title, "Alpha")
        XCTAssertEqual(tabs[1].title, "Beta\textra")        // tab-in-title preserved
    }
}
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests PASS (including `testAppleScriptOutputParsing`).

- [ ] **Step 4: Manual live verification**

Run: `swift run macmem`
Expected: prints three sections. macOS shows an Automation permission prompt for each running browser the first time — approve it. With Brave/Chrome/Safari open, the BROWSER TABS section lists real URLs. Without approval, the section shows the permission-needed note and the rest still prints.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AppleScriptTabSource live browser bridge + parser test"
```

---

## Task 13: README + manual end-to-end check

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# macmem

A macOS CLI that shows where your memory is going:

- **Top apps** by combined footprint (helper/renderer processes collapsed into their app).
- **Swap** total plus a confidence-labeled estimate of likely contributors.
- **Browser tabs** (Safari / Brave / Chrome / Edge) with URLs and best-effort per-tab estimates.

> Per-tab memory and per-app swap are **estimates** — macOS does not expose them
> directly. They are always labeled with confidence and left blank when ambiguous.

## Install (from source)

```bash
swift build -c release
cp .build/release/macmem /usr/local/bin/
```

## Usage

```bash
macmem                 # full snapshot
macmem --json          # machine-readable
macmem --top 5         # 5 per section
macmem --no-tabs       # skip browser tabs
macmem --watch 2       # refresh every 2s
sudo macmem            # include root-owned processes
```

The first run prompts for **Automation** access per browser (needed to read tab URLs).
For full process coverage including system/root processes, run with `sudo`.

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 2: Full release build + smoke run**

Run: `swift build -c release && .build/release/macmem --top 5`
Expected: three sections print with real data for your user's apps.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: add README"
```

---

## Task 14: Homebrew formula + CI

**Files:**
- Create: `Formula/macmem.rb`
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write `Formula/macmem.rb`**

```ruby
class Macmem < Formula
  desc "macOS CLI: heaviest apps, swap usage, and browser tabs"
  homepage "https://github.com/OWNER/macmem"
  url "https://github.com/OWNER/macmem/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/macmem"
  end

  test do
    assert_match "TOP APPS", shell_output("#{bin}/macmem --no-tabs --no-swap")
  end
end
```

Note: `OWNER` and the `sha256` are filled at first release (`shasum -a 256` of the GitHub-generated tag tarball). This formula goes in a tap repo (`homebrew-macmem`) for `brew install OWNER/macmem/macmem`.

- [ ] **Step 2: Write `.github/workflows/ci.yml`**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Show Swift version
        run: swift --version
      - name: Build
        run: swift build -c release
      - name: Test
        run: swift test
```

- [ ] **Step 3: Verify the test command the formula uses works**

Run: `swift build -c release && .build/release/macmem --no-tabs --no-swap`
Expected: output contains `TOP APPS`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "build: add Homebrew formula and GitHub Actions CI"
```

---

## Self-Review

**Spec coverage check (against `2026-06-05-macmem-mac-memory-monitor-design.md`):**

- §1 top-10 apps combined → Tasks 4, 9 (grouping + native footprint). ✓
- §1 swap total + culprits → Tasks 5, 9. ✓
- §1 top browser tabs + URLs → Tasks 6, 12. ✓
- §2 `MemoryProvider` protocol + native default + future shell-out seam → Task 3, 9. ✓
- §2 estimates with confidence, blank when ambiguous → Tasks 5, 6 (count-match guard), 8 (`~`/`n/a` markers). ✓
- §3 privilege: CLI sudo hint to stderr → Task 11; unreadable processes listed → Task 9. ✓
- §3 Automation TCC + graceful denial → Tasks 7 (`.partial`/`.permissionNeeded`), 12. ✓
- §4.1 repo layout → Task 1 + file structure. ✓
- §4.2 `phys_footprint` (Activity-Monitor parity) → Task 9 (`ri_phys_footprint`). ✓
- §4.2 swap ins/outs from `host_statistics64` (not `vm.swapusage`) → Task 9 (`swapInOut`). ✓
- §4.2 responsible-PID as private API, default-off, public fallback → Tasks 4 (fallback) + 10 (private wrapper). ✓
- §4.2 `ri_pageins` noisy-proxy caveat → Task 5 (doc comment + confidence). ✓
- §5 CLI flags (`--json`, `--watch`, `--top`, `--no-tabs`, `--no-swap`) → Task 11. ✓
- §7 Homebrew formula → Task 14. ✓ (Cask/notarization belong to the MenuBar plan.)
- §8 testing via fakes through the protocol → Tasks 3–8; native smoke test → Task 9. ✓
- §9 per-section fault isolation → Task 7. ✓

**Type consistency:** `MemoryProvider.listProcesses()`/`readSwap()`, `AppGrouper.group(_:topN:)`, `SwapEstimator.culprits(groups:samples:swap:topN:)`, `BrowserInspector.topTabs(rendererFootprintsByBrowser:topN:)`, `TabSource.runningBrowsers()`/`tabs(for:)`, `SnapshotBuilder(provider:tabSource:).build(topN:includeTabs:includeSwap:)`, `TextRenderer.render(_:)`, `JSONRenderer.render(_:)`, `ByteFormat.string(_:)` — all names used consistently across tasks. ✓

**Placeholder scan:** No `TBD`/`TODO`/"handle edge cases" left. The two intentional release-time blanks (`OWNER`, `sha256` in the Homebrew formula) are documented as fill-at-release, not implementation gaps. ✓

**Build-order note:** Task 11 (CLI) references `AppleScriptTabSource` from Task 12. Implement Task 12 immediately after Task 11 (or temporarily pass `nil` as noted) so the executable compiles. All other tasks compile independently.

---

## Follow-up: Plan 2 (MenuBar app)

Not in this plan. Plan 2 builds the SwiftUI `MenuBarExtra` app on the now-proven `MacMemCore`: status-item metric, dropdown sections, timer polling, the `SMAppService` privileged-helper "Enable full access" path, the "Grant Automation" banner, launch-at-login, Homebrew Cask + Developer-ID notarization. Write it after this plan lands.
