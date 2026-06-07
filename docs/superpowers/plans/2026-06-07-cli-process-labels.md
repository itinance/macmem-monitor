# Directory-Aware Labels for CLI Process Groups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disambiguate bundle-less CLI process groups (`make`, `node`, `python`) by their working directory and raw argv so unrelated trees stop collapsing under one bare name, in both the TOP APPS and SWAP/compressed sections.

**Architecture:** Capture two best-effort fields (`workingDirectory`, `commandLine`) on `ProcessSample` in `NativeMemoryProvider`. A new pure `ProcessLabel` helper holds all label string logic (group key, shortest-unique-suffix, display strings). `AppGrouper` keys bundle-less groups by `(name, cwd)`, then assigns each group a directory-aware display name; the compressed aggregator inherits the label for free (single labeling site). `TextRenderer` is fixed to auto-size the TOP APPS name column and middle-truncate (preserving the trailing argv token) instead of tail-cutting. A `--full-paths` CLI flag threads a `PathStyle` through `SnapshotBuilder` into `AppGrouper`.

**Tech Stack:** Swift 6.3 / SwiftPM, swift-argument-parser, Darwin (`proc_pidinfo` PROC_PIDVNODEPATHINFO, `sysctl` KERN_PROCARGS2), XCTest. Target macOS 13+ (running macOS 26).

**Spec:** `docs/superpowers/specs/2026-06-07-cli-process-labels-design.md` (Status: Approved).

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `Sources/MacMemCore/Models.swift` | Data types | Add `workingDirectory`/`commandLine` to `ProcessSample` (default `nil`). |
| `Sources/MacMemCore/ProcessLabel.swift` | **NEW.** Pure label string logic + `PathStyle` enum. | Create. |
| `Sources/MacMemCore/AppGrouper.swift` | Group processes into apps | Thread cwd/argv through owner resolution; key bundle-less by `(name, cwd)`; assign directory-aware display names; add `pathStyle`/`homeDirectory` params. |
| `Sources/MacMemCore/TextRenderer.swift` | Text table rendering | Replace fixed-width tail-truncation with auto-size + `middleTruncate`. |
| `Sources/MacMemCore/SnapshotBuilder.swift` | Orchestration | Add `pathStyle` param to `build`, pass to `AppGrouper.group`. |
| `Sources/MacMemCore/NativeMemoryProvider.swift` | Native data source | Read cwd + argv per pid; populate the new fields. |
| `Sources/macmem/main.swift` | CLI | Add `--full-paths` flag → `PathStyle`. |
| `README.md` | Docs | Document `--full-paths`. |
| `Tests/MacMemCoreTests/ProcessLabelTests.swift` | **NEW.** Unit tests for pure logic. | Create. |
| `Tests/MacMemCoreTests/AppGrouperTests.swift` | Grouping tests | Add new cases; update existing bundle-less assertions. |
| `Tests/MacMemCoreTests/RendererTests.swift` | Renderer tests | Add `middleTruncate`/auto-size cases. |
| `Tests/MacMemCoreTests/SnapshotBuilderTests.swift` | Builder tests | Add `pathStyle` threading case. |
| `Tests/MacMemCoreTests/NativeProviderSmokeTests.swift` | Native smoke tests | Add cwd/argv self-pid case. |

**Key design facts the implementer must respect:**
- `ProcessSample.init` (`Models.swift:23`) is a public memberwise init with NO defaults today and is called in `NativeMemoryProvider` (2 sites) and many tests. The two new params **MUST** default `= nil` so all existing call sites compile unchanged.
- `PathStyle` is consumed by `SnapshotBuilder.build` (public) and `main.swift` (plain `import MacMemCore`, not `@testable`), so `PathStyle` **MUST** be `public`. `ProcessLabel` itself is only used inside `MacMemCore` and exercised via `@testable import`, so it stays `internal`.
- `middleTruncate` is unit-tested directly, so it must be `internal` (no `private`), reachable via `@testable import`.
- There is a **single labeling site**: `AppGrouper` writes the display string into `AppGroup.name`; `CompressedMemoryAggregator.entries` (`CompressedMemoryAggregator.swift:19`) copies `group.name` into `CompressedMemoryEntry.appName`. Do not relabel in the aggregator or renderer.
- macOS 26 Swift-overlay friction: `PROC_PIDPATHINFO_MAXSIZE` was not importable (`NativeMemoryProvider.swift:79-82` hardcodes `4 * Int(MAXPATHLEN)`). Hardcode `PROC_PIDVNODEPATHINFO` (= 9) and `KERN_PROCARGS2` (= 49) the same way to avoid relying on macro imports.

---

### Task 1: Add `workingDirectory` and `commandLine` to `ProcessSample`

**Files:**
- Modify: `Sources/MacMemCore/Models.swift:11-31`

- [ ] **Step 1: Add the two stored properties and init params (with defaults)**

In `Sources/MacMemCore/Models.swift`, replace the `ProcessSample` struct (lines 11-31) with:

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
    public let isReadable: Bool
    /// Absolute current working directory, best-effort. `nil` when unreadable (other
    /// users' processes without sudo, or any error). Used to disambiguate CLI groups.
    public let workingDirectory: String?
    /// Raw process arguments after the executable path, space-joined and trimmed.
    /// `nil` when unreadable or empty. For `make -j8 run-api` this is `-j8 run-api`.
    public let commandLine: String?

    public init(pid: Int32, ppid: Int32, responsiblePID: Int32?, bundleID: String?,
                name: String, executablePath: String?, footprintBytes: UInt64,
                residentBytes: UInt64, pageIns: UInt64, isReadable: Bool,
                workingDirectory: String? = nil, commandLine: String? = nil) {
        self.pid = pid; self.ppid = ppid; self.responsiblePID = responsiblePID
        self.bundleID = bundleID; self.name = name; self.executablePath = executablePath
        self.footprintBytes = footprintBytes; self.residentBytes = residentBytes
        self.pageIns = pageIns; self.isReadable = isReadable
        self.workingDirectory = workingDirectory; self.commandLine = commandLine
    }
}
```

- [ ] **Step 2: Build to verify all existing call sites still compile**

Run: `swift build`
Expected: builds with no errors (the `= nil` defaults keep every existing `ProcessSample(...)` call site valid).

- [ ] **Step 3: Run the suite to confirm nothing regressed**

Run: `swift test`
Expected: PASS (same count as before — no behavior change yet).

- [ ] **Step 4: Commit**

```bash
git add Sources/MacMemCore/Models.swift
git commit -m "$(cat <<'EOF'
feat: add workingDirectory and commandLine to ProcessSample

Best-effort optional fields (default nil) used to disambiguate
bundle-less CLI process groups by directory + argv.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `ProcessLabel` pure helper + `PathStyle`

**Files:**
- Create: `Sources/MacMemCore/ProcessLabel.swift`
- Test: `Tests/MacMemCoreTests/ProcessLabelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MacMemCoreTests/ProcessLabelTests.swift`:

```swift
import XCTest
@testable import MacMemCore

final class ProcessLabelTests: XCTestCase {
    // groupKey: three cases from the spec.
    func testGroupKeyUsesBaseBundleIDWhenPresent() {
        XCTAssertEqual(
            ProcessLabel.groupKey(name: "Brave Browser", baseBundleID: "com.brave.Browser",
                                  workingDirectory: "/anywhere"),
            "com.brave.Browser")
    }

    func testGroupKeySplitsBundlelessByDirectory() {
        let a = ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: "/x/a")
        let b = ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: "/x/b")
        XCTAssertNotEqual(a, b)
        // Same name + same cwd collapses to one key.
        XCTAssertEqual(a, ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: "/x/a"))
    }

    func testGroupKeyBundlelessNilCwdCollapsesToName() {
        XCTAssertEqual(
            ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: nil),
            "make")
    }

    // shortestUniqueSuffixes: tail-colliding cohort needs 2 components.
    func testShortestUniqueSuffixesDisambiguatesCommonTail() {
        let result = ProcessLabel.shortestUniqueSuffixes([
            "/Users/me/hotfix/apps/backend",
            "/Users/me/uitweaks/apps/backend",
        ])
        XCTAssertEqual(result["/Users/me/hotfix/apps/backend"], "hotfix/apps/backend")
        XCTAssertEqual(result["/Users/me/uitweaks/apps/backend"], "uitweaks/apps/backend")
    }

    func testShortestUniqueSuffixesSingletonIsLastComponent() {
        let result = ProcessLabel.shortestUniqueSuffixes(["/Users/me/project/backend"])
        XCTAssertEqual(result["/Users/me/project/backend"], "backend")
    }

    // Suffix-of-suffix tiebreak: /a/b/c vs /b/c can't both be separated by a trailing
    // suffix — the shorter path must fall back (absent from the map → caller uses full path).
    func testShortestUniqueSuffixesSuffixOfSuffixFallsBack() {
        let result = ProcessLabel.shortestUniqueSuffixes(["/a/b/c", "/b/c"])
        // The shorter path (/b/c) has no trailing suffix that excludes /a/b/c, so it is
        // omitted; the caller renders its full path. The map must not assign both the
        // same string.
        XCTAssertNil(result["/b/c"])
        // The longer path resolves at full depth.
        XCTAssertEqual(result["/a/b/c"], "a/b/c")
    }

    // abbreviateHome.
    func testAbbreviateHomeReplacesPrefix() {
        XCTAssertEqual(ProcessLabel.abbreviateHome("/Users/me/x/y", home: "/Users/me"), "~/x/y")
        XCTAssertEqual(ProcessLabel.abbreviateHome("/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(ProcessLabel.abbreviateHome("/opt/tool", home: "/Users/me"), "/opt/tool")
    }

    // displayLabel: shortestUnique vs collapsed vs raw-argv suffix.
    func testDisplayLabelWithDirAndRawArgv() {
        // Raw argv renders verbatim — NOT cleaned to just the target.
        XCTAssertEqual(
            ProcessLabel.displayLabel(name: "make", dirDisplay: "apps/backend", commandLine: "-j8 run-api"),
            "make — apps/backend (-j8 run-api)")
    }

    func testDisplayLabelWithDirNoArgv() {
        XCTAssertEqual(
            ProcessLabel.displayLabel(name: "make", dirDisplay: "apps/backend", commandLine: nil),
            "make — apps/backend")
    }

    func testCollapsedLabelPluralizes() {
        XCTAssertEqual(ProcessLabel.collapsedLabel(name: "make", processCount: 1),
                       "make  (1 process, dir unavailable)")
        XCTAssertEqual(ProcessLabel.collapsedLabel(name: "make", processCount: 3),
                       "make  (3 processes, dir unavailable)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessLabelTests`
Expected: FAIL to compile — `ProcessLabel` / `PathStyle` not defined.

- [ ] **Step 3: Create the implementation**

Create `Sources/MacMemCore/ProcessLabel.swift`:

```swift
import Foundation

/// How the directory portion of a bundle-less CLI label is rendered.
public enum PathStyle: Sendable {
    /// Fewest trailing path components that stay unique within the same-name cohort.
    case shortestUnique
    /// The full `$HOME`-abbreviated (`~/…`) path.
    case fullPath
}

/// Pure string logic for labeling bundle-less CLI process groups (no I/O).
/// `AppGrouper` orchestrates; this computes group keys and display strings so the
/// logic is unit-testable in isolation.
enum ProcessLabel {

    /// Grouping key for a resolved owner:
    /// - base bundle ID present → that ID (existing app-grouping behavior).
    /// - bundle-less + cwd present → `"name\u{0}cwd"` (split per directory).
    /// - bundle-less + cwd nil → `name` (collapse all unreadable same-name processes).
    static func groupKey(name: String, baseBundleID: String?, workingDirectory: String?) -> String {
        if let bundleID = baseBundleID { return bundleID }
        if let cwd = workingDirectory { return "\(name)\u{0}\(cwd)" }
        return name
    }

    /// Per-cwd shortest trailing path-component suffix (minimum 1 component) that is
    /// unique within the cohort. A cwd that no trailing suffix can separate from another
    /// (its components are a suffix of the other's) is omitted from the result; the
    /// caller falls back to the full `~`-abbreviated path for those, keeping rows distinct.
    static func shortestUniqueSuffixes(_ paths: [String]) -> [String: String] {
        let componentsByPath: [String: [String]] = Dictionary(uniqueKeysWithValues:
            paths.map { ($0, $0.split(separator: "/").map(String.init)) })
        var result: [String: String] = [:]
        for path in paths {
            guard let mine = componentsByPath[path], !mine.isEmpty else { continue }
            for depth in 1...mine.count {
                let suffix = mine.suffix(depth).joined(separator: "/")
                let collides = paths.contains { other in
                    other != path
                        && componentsByPath[other]?.suffix(depth).joined(separator: "/") == suffix
                }
                if !collides {
                    result[path] = suffix
                    break
                }
            }
        }
        return result
    }

    /// Replaces a leading `home` path with `~`.
    static func abbreviateHome(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Label for a bundle-less group whose cwd is known. `dirDisplay` is the already
    /// resolved directory string (shortest-unique suffix or `~`-abbreviated full path).
    static func displayLabel(name: String, dirDisplay: String, commandLine: String?) -> String {
        if let command = commandLine, !command.isEmpty {
            return "\(name) — \(dirDisplay) (\(command))"
        }
        return "\(name) — \(dirDisplay)"
    }

    /// Label for a bundle-less group whose cwd could not be read (bare-name collapse).
    static func collapsedLabel(name: String, processCount: Int) -> String {
        let noun = processCount == 1 ? "process" : "processes"
        return "\(name)  (\(processCount) \(noun), dir unavailable)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessLabelTests`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacMemCore/ProcessLabel.swift Tests/MacMemCoreTests/ProcessLabelTests.swift
git commit -m "$(cat <<'EOF'
feat: add ProcessLabel pure helper and PathStyle

Group-key, shortest-unique-suffix (with suffix-of-suffix fallback),
home abbreviation, and display/collapsed label strings for
bundle-less CLI process groups.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `AppGrouper` directory-aware identity + labels

**Files:**
- Modify: `Sources/MacMemCore/AppGrouper.swift` (full rewrite of `group`/`resolveOwner`/`Acc`)
- Test: `Tests/MacMemCoreTests/AppGrouperTests.swift` (add cases; update 4 existing assertions)

- [ ] **Step 1: Write the failing tests (new behavior)**

In `Tests/MacMemCoreTests/AppGrouperTests.swift`, first **extend the `sample` helper** (lines 5-10) to accept the new fields:

```swift
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        responsible: Int32? = nil, ppid: Int32 = 0,
                        cwd: String? = nil, cmd: String? = nil) -> ProcessSample {
        ProcessSample(pid: pid, ppid: ppid, responsiblePID: responsible, bundleID: bundle,
                      name: name, executablePath: nil, footprintBytes: footprint,
                      residentBytes: footprint, pageIns: 0, isReadable: true,
                      workingDirectory: cwd, commandLine: cmd)
    }
```

Then append these new test methods (before the final closing brace):

```swift
    // Same name + different cwd → separate, directory-labeled groups.
    func testBundlelessSameNameDifferentCwdSplits() {
        let samples = [
            sample(1, name: "make", bundle: nil, footprint: 100, ppid: 1,
                   cwd: "/Users/me/hotfix/apps/backend", cmd: "run-api"),
            sample(2, name: "make", bundle: nil, footprint: 200, ppid: 1,
                   cwd: "/Users/me/uitweaks/apps/backend", cmd: "worker"),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 2, "different cwd → separate groups")
        let names = Set(groups.map { $0.name })
        XCTAssertTrue(names.contains("make — hotfix/apps/backend (run-api)"))
        XCTAssertTrue(names.contains("make — uitweaks/apps/backend (worker)"))
    }

    // Same name + same cwd → one merged group; representative argv = highest footprint.
    func testBundlelessSameNameSameCwdMerges() {
        let samples = [
            sample(1, name: "make", bundle: nil, footprint: 50, ppid: 1,
                   cwd: "/Users/me/proj/backend", cmd: "small"),
            sample(2, name: "make", bundle: nil, footprint: 500, ppid: 1,
                   cwd: "/Users/me/proj/backend", cmd: "big"),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1, "same name + same cwd merges")
        XCTAssertEqual(groups[0].totalFootprintBytes, 550)
        XCTAssertEqual(groups[0].processCount, 2)
        // Singleton cohort → last component; argv from the heavier process.
        XCTAssertEqual(groups[0].name, "make — backend (big)")
    }

    // Bundle-less + nil cwd → single collapsed bare-name group.
    func testBundlelessNilCwdCollapsesToBareName() {
        let samples = [
            sample(1, name: "make", bundle: nil, footprint: 10, ppid: 1),
            sample(2, name: "make", bundle: nil, footprint: 20, ppid: 1),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1, "unreadable-cwd same-name processes collapse")
        XCTAssertEqual(groups[0].name, "make  (2 processes, dir unavailable)")
        XCTAssertEqual(groups[0].totalFootprintBytes, 30)
    }

    // pathStyle: .fullPath produces ~-abbreviated labels regardless of uniqueness.
    func testFullPathStyleProducesHomeAbbreviatedLabels() {
        let samples = [
            sample(1, name: "node", bundle: nil, footprint: 100, ppid: 1,
                   cwd: "/Users/me/svc/api", cmd: "index.js"),
        ]
        let groups = AppGrouper().group(samples, topN: 10, pathStyle: .fullPath,
                                        homeDirectory: "/Users/me")
        XCTAssertEqual(groups[0].name, "node — ~/svc/api (index.js)")
    }
```

- [ ] **Step 2: Update the four existing assertions broken by the collapse behavior**

These existing tests use bundle-less samples with nil cwd, which now render as collapsed labels. Update them:

In `testBundlelessProcessWithLaunchdParentStaysOwnGroup` (was asserting `groups[0].name == "somecli"`):
```swift
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].name.hasPrefix("somecli"), "bare name preserved in collapsed label")
        XCTAssertNil(groups[0].bundleID)
```

In `testBundlelessProcessWithMissingParentStaysOwnGroup`:
```swift
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].name.hasPrefix("helper"), "bare name preserved in collapsed label")
        XCTAssertNil(groups[0].bundleID)
```

In `testPPIDCycleDoesNotInfiniteLoop` (replace the `names == ["cycleA","cycleB"]` assertion):
```swift
        XCTAssertEqual(groups.count, 2, "both bundle-less cycle members stay as separate groups")
        let names = groups.map { $0.name }.sorted()
        XCTAssertTrue(names[0].hasPrefix("cycleA"))
        XCTAssertTrue(names[1].hasPrefix("cycleB"))
```

In `testBundlelessChildOfShellDoesNotFoldThroughShellIntoApp` (the `swift-build` group is now collapse-labeled; the Ghostty group is unchanged). Replace the `swiftGroup` lookup:
```swift
        let swiftGroup = groups.first { $0.name.hasPrefix("swift-build") }
        XCTAssertNotNil(swiftGroup)
        XCTAssertEqual(swiftGroup?.totalFootprintBytes, 150)
        XCTAssertEqual(swiftGroup?.processCount, 1)
```
(Leave the `byName["Ghostty"]` lookup as-is — Ghostty has a bundle ID and keeps its name.)

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `swift test --filter AppGrouperTests`
Expected: FAIL — new label expectations not met (old `AppGrouper` still keys by bare name and does not relabel).

- [ ] **Step 4: Rewrite `AppGrouper`**

Replace the entire body of `AppGrouper` in `Sources/MacMemCore/AppGrouper.swift` (the `public struct AppGrouper { ... }` block, lines 9-83) with:

```swift
public struct AppGrouper {
    public init() {}

    private struct Owner {
        let name: String
        let bundleID: String?
        let workingDirectory: String?
        let commandLine: String?
    }

    private struct Acc {
        var name: String
        var bundleID: String?
        var workingDirectory: String?
        var commandLine: String?   // representative: argv of the highest-footprint member
        var repFootprint: UInt64
        var total: UInt64
        var pids: [Int32]
    }

    public func group(_ samples: [ProcessSample], topN: Int = 10,
                      pathStyle: PathStyle = .shortestUnique,
                      homeDirectory: String = NSHomeDirectory()) -> [AppGroup] {
        let limit = max(0, topN)
        let byPID = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        var groups: [String: Acc] = [:]
        for s in samples {
            let owner = resolveOwner(s, byPID: byPID)
            let key = ProcessLabel.groupKey(name: owner.name, baseBundleID: owner.bundleID,
                                            workingDirectory: owner.workingDirectory)
            if var acc = groups[key] {
                acc.total += s.footprintBytes
                acc.pids.append(s.pid)
                if s.footprintBytes > acc.repFootprint {
                    acc.repFootprint = s.footprintBytes
                    acc.commandLine = owner.commandLine
                }
                groups[key] = acc
            } else {
                groups[key] = Acc(name: owner.name, bundleID: owner.bundleID,
                                  workingDirectory: owner.workingDirectory,
                                  commandLine: owner.commandLine,
                                  repFootprint: s.footprintBytes,
                                  total: s.footprintBytes, pids: [s.pid])
            }
        }

        // Shortest-unique suffixes per same-name cohort of bundle-less directory groups.
        // Computed over ALL such groups (before the topN cut) so labels stay stable
        // regardless of truncation and across the TOP APPS / SWAP sections.
        let dirAccs = groups.values.filter { $0.bundleID == nil && $0.workingDirectory != nil }
        var suffixesByName: [String: [String: String]] = [:]
        for (name, accs) in Dictionary(grouping: dirAccs, by: { $0.name }) {
            let paths = Array(Set(accs.compactMap { $0.workingDirectory }))
            suffixesByName[name] = ProcessLabel.shortestUniqueSuffixes(paths)
        }

        return groups.values
            .map { acc -> AppGroup in
                let display = displayName(for: acc, pathStyle: pathStyle,
                                          home: homeDirectory, suffixesByName: suffixesByName)
                return AppGroup(name: display, bundleID: acc.bundleID,
                                totalFootprintBytes: acc.total,
                                processCount: acc.pids.count, pids: acc.pids.sorted())
            }
            .sorted { $0.totalFootprintBytes > $1.totalFootprintBytes }
            .prefix(limit)
            .map { $0 }
    }

    private func displayName(for acc: Acc, pathStyle: PathStyle, home: String,
                             suffixesByName: [String: [String: String]]) -> String {
        // App with a bundle ID: keep its current name unchanged.
        if acc.bundleID != nil { return acc.name }
        // Bundle-less with a readable cwd: directory-aware label.
        if let cwd = acc.workingDirectory {
            let dirDisplay: String
            switch pathStyle {
            case .fullPath:
                dirDisplay = ProcessLabel.abbreviateHome(cwd, home: home)
            case .shortestUnique:
                dirDisplay = suffixesByName[acc.name]?[cwd]
                    ?? ProcessLabel.abbreviateHome(cwd, home: home)
            }
            return ProcessLabel.displayLabel(name: acc.name, dirDisplay: dirDisplay,
                                             commandLine: acc.commandLine)
        }
        // Bundle-less, cwd unreadable: collapsed bare-name row.
        return ProcessLabel.collapsedLabel(name: acc.name, processCount: acc.pids.count)
    }

    private func resolveOwner(_ s: ProcessSample, byPID: [Int32: ProcessSample],
                              visited: Set<Int32> = []) -> Owner {
        var visited = visited
        guard visited.insert(s.pid).inserted else {
            return terminalOwner(s)
        }
        // Step 1: responsiblePID (highest-fidelity signal, requires private API/entitlement).
        if let rpid = s.responsiblePID, rpid != s.pid, let owner = byPID[rpid] {
            return resolveOwner(owner, byPID: byPID, visited: visited)
        }
        // Step 2: process has its own bundle ID → it is an app. Keep its identity.
        if s.bundleID != nil {
            return terminalOwner(s)
        }
        // Step 3: PPID fallback — fold bundle-less children into a launching *app* parent.
        if s.ppid > 1, let parent = byPID[s.ppid], parent.bundleID != nil {
            return resolveOwner(parent, byPID: byPID, visited: visited)
        }
        // Step 4: no usable owner signal — return the process under its own name.
        return terminalOwner(s)
    }

    /// The owner is the process itself. Apps carry no cwd/argv; bundle-less CLI
    /// processes carry theirs so the label can disambiguate them.
    private func terminalOwner(_ s: ProcessSample) -> Owner {
        if let bundleID = s.bundleID {
            return Owner(name: Self.cleanName(s.name), bundleID: Self.baseBundleID(bundleID),
                         workingDirectory: nil, commandLine: nil)
        }
        return Owner(name: Self.cleanName(s.name), bundleID: nil,
                     workingDirectory: s.workingDirectory, commandLine: s.commandLine)
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

(Leave the file's leading `import Foundation` and the doc comment above the struct intact.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AppGrouperTests`
Expected: PASS (new cases + updated existing assertions). The total-conservation cycle tests still hold (grouping never drops or double-counts footprint).

- [ ] **Step 6: Commit**

```bash
git add Sources/MacMemCore/AppGrouper.swift Tests/MacMemCoreTests/AppGrouperTests.swift
git commit -m "$(cat <<'EOF'
feat: split bundle-less CLI groups by working directory + argv

AppGrouper keys bundle-less owners by (name, cwd), assigns each group
a directory-aware display name via ProcessLabel (shortest-unique suffix
by default, full ~-path with .fullPath), and collapses unreadable-cwd
same-name processes into a single bare-name row. Apps with bundle IDs
keep their names. Adds pathStyle and homeDirectory params.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `TextRenderer` auto-size + `middleTruncate`

**Files:**
- Modify: `Sources/MacMemCore/TextRenderer.swift`
- Test: `Tests/MacMemCoreTests/RendererTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MacMemCoreTests/RendererTests.swift` (before the final closing brace):

```swift
    // middleTruncate preserves the head and the trailing token; ellipsis sits in the middle.
    func testMiddleTruncatePreservesHeadAndTail() {
        let s = "make — projectAlpha/services/backend (worker-multi-2)"
        let out = TextRenderer.middleTruncate(s, width: 30)
        XCTAssertEqual(out.count, 30, "truncated label must be exactly the requested width")
        XCTAssertTrue(out.hasPrefix("make"), "process name must survive at the head")
        XCTAssertTrue(out.hasSuffix("2)"), "trailing argv token must survive at the tail")
        XCTAssertTrue(out.contains("…"), "middle truncation uses an ellipsis")
    }

    // A label at or under the width is returned unchanged.
    func testMiddleTruncateNoOpWhenWithinWidth() {
        XCTAssertEqual(TextRenderer.middleTruncate("short", width: 30), "short")
    }

    // Degenerate: name + trailing token alone exceed the cap — name must NOT be dropped.
    func testMiddleTruncateDegenerateKeepsName() {
        let s = "make — " + String(repeating: "x", count: 200) + " (run-api-target)"
        let out = TextRenderer.middleTruncate(s, width: 60)
        XCTAssertEqual(out.count, 60)
        XCTAssertTrue(out.hasPrefix("make"), "process name must never be silently dropped")
        XCTAssertTrue(out.hasSuffix(")"), "trailing token end must survive")
    }

    // TOP APPS auto-sizes the name column to the longest shown label, capped at 60,
    // and middle-truncates only beyond the cap (trailing argv token survives).
    func testTopAppsAutoSizesAndMiddleTruncatesOverCap() {
        let longLabel = "make — " + String(repeating: "deep/", count: 30) + "backend (worker-multi-2)"
        let snap = MemorySnapshot(
            topApps: [
                AppGroup(name: "node — svc/api (index.js)", bundleID: nil,
                         totalFootprintBytes: 100, processCount: 1, pids: [1]),
                AppGroup(name: longLabel, bundleID: nil,
                         totalFootprintBytes: 200, processCount: 2, pids: [2, 3]),
            ],
            appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            topTabs: [], tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        // The shorter, under-cap label renders in full.
        XCTAssertTrue(out.contains("node — svc/api (index.js)"))
        // The over-cap label is middle-truncated but keeps its name and trailing token.
        XCTAssertTrue(out.contains("…"), "over-cap label must be middle-truncated")
        XCTAssertTrue(out.contains("(worker-multi-2)"), "trailing argv token must survive truncation")
        XCTAssertTrue(out.contains("make — "), "process name + dir head must survive truncation")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RendererTests`
Expected: FAIL — `TextRenderer.middleTruncate` not defined; auto-size not implemented.

- [ ] **Step 3: Implement the renderer changes**

In `Sources/MacMemCore/TextRenderer.swift`:

(a) Replace the name-column constants and `nameColumn` helper (lines 4-21) with:

```swift
    // Column widths for fixed-width table layout.
    // NAME_WIDTH_MAX: the TOP APPS name column auto-sizes to the longest shown label,
    // capped here. Labels beyond the cap are middle-truncated (head + trailing token kept).
    private static let nameWidthMax = 60
    // MEM_WIDTH: characters reserved for the right-aligned memory string (e.g. "  1.5 MB").
    private static let memWidth = 10
    // TAB_MEM_WIDTH: characters reserved for the tab memory field (includes "~" prefix and label).
    private static let tabMemWidth = 20

    /// Truncates `s` to exactly `width` characters by removing the middle and inserting
    /// an ellipsis, preserving the head (process name) and the tail (trailing argv token).
    /// Strings already within `width` are returned unchanged.
    static func middleTruncate(_ s: String, width: Int) -> String {
        if s.count <= width { return s }
        guard width >= 2 else { return String(s.prefix(max(0, width))) }
        let budget = width - 1                 // room left after the ellipsis
        let headLen = budget - budget / 2      // bias the head when budget is odd
        let tailLen = budget / 2
        return "\(s.prefix(headLen))…\(s.suffix(tailLen))"
    }
```

(b) Replace the TOP APPS loop (lines 32-38) with:

```swift
        lines.append("== TOP APPS (by combined memory) ==")
        lines.append(statusNote(snap.appsStatus, unreadable: snap.unreadableProcessCount))
        let nameFieldWidth = min(snap.topApps.map { $0.name.count }.max() ?? 0, nameWidthMax)
        for (i, app) in snap.topApps.enumerated() {
            let label = middleTruncate(app.name, width: nameFieldWidth)
            let name = label.padding(toLength: nameFieldWidth, withPad: " ", startingAt: 0)
            let mem  = memColumn(ByteFormat.string(app.totalFootprintBytes))
            lines.append(String(format: "%2d. %@  %@  (%d proc)", i + 1, name, mem, app.processCount))
        }
```

(The `memColumn` helper, SWAP, and BROWSER TABS sections are unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RendererTests`
Expected: PASS — including the existing `testTopAppsColumnsAlignAcrossShortAndLongNames` (the long WebKit name exceeds 60 → middle-truncated with "…", both rows pad to the same width so the memory column stays aligned).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacMemCore/TextRenderer.swift Tests/MacMemCoreTests/RendererTests.swift
git commit -m "$(cat <<'EOF'
fix: auto-size TOP APPS name column and middle-truncate labels

Replaces the fixed 30-char tail-truncation (which cut the disambiguating
directory + argv token the new labels add) with a column sized to the
longest shown label, capped at 60, and a middle-truncation that preserves
the process name and the trailing argv token.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Thread `pathStyle` through `SnapshotBuilder`

**Files:**
- Modify: `Sources/MacMemCore/SnapshotBuilder.swift:18,27`
- Test: `Tests/MacMemCoreTests/SnapshotBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/MacMemCoreTests/SnapshotBuilderTests.swift` (before the final closing brace). First extend the local `sample` helper (lines 7-12) to pass cwd:

```swift
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        pageIns: UInt64 = 0, readable: Bool = true,
                        cwd: String? = nil, cmd: String? = nil) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: bundle, name: name,
                      executablePath: nil, footprintBytes: footprint, residentBytes: footprint,
                      pageIns: pageIns, isReadable: readable,
                      workingDirectory: cwd, commandLine: cmd)
    }
```

Then add:

```swift
    func testPathStyleThreadsThroughToLabels() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "node", bundle: nil, footprint: 100,
                               cwd: "/Users/me/svc/api", cmd: "index.js")],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        // Default style is shortestUnique: a singleton cohort shows its last component.
        let def = SnapshotBuilder(provider: provider, tabSource: nil).build(includeSwap: false)
        XCTAssertEqual(def.topApps.first?.name, "node — api (index.js)")
        // .fullPath shows the full path (here unabbreviated — home differs from the test path).
        let full = SnapshotBuilder(provider: provider, tabSource: nil)
            .build(includeSwap: false, pathStyle: .fullPath)
        XCTAssertEqual(full.topApps.first?.name, "node — /Users/me/svc/api (index.js)")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SnapshotBuilderTests/testPathStyleThreadsThroughToLabels`
Expected: FAIL to compile — `build` has no `pathStyle` parameter.

- [ ] **Step 3: Add the parameter and pass it through**

In `Sources/MacMemCore/SnapshotBuilder.swift`, change the `build` signature (line 18) and the `AppGrouper().group` call (line 27):

```swift
    public func build(topN: Int = 10, includeTabs: Bool = true, includeSwap: Bool = true,
                      pathStyle: PathStyle = .shortestUnique) -> MemorySnapshot {
```

```swift
            topApps = AppGrouper().group(samples.filter { $0.isReadable }, topN: topN,
                                         pathStyle: pathStyle)
```

(`homeDirectory` keeps its `NSHomeDirectory()` default — no need to thread it through the builder.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SnapshotBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacMemCore/SnapshotBuilder.swift Tests/MacMemCoreTests/SnapshotBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat: thread PathStyle through SnapshotBuilder.build

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Native cwd + argv readers in `NativeMemoryProvider`

**Files:**
- Modify: `Sources/MacMemCore/NativeMemoryProvider.swift`
- Test: `Tests/MacMemCoreTests/NativeProviderSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Append to `Tests/MacMemCoreTests/NativeProviderSmokeTests.swift` (before the final closing brace):

```swift
    func testReadsWorkingDirectoryForOwnProcess() throws {
        let provider = NativeMemoryProvider()
        let processes = try provider.listProcesses()
        let me = ProcessInfo.processInfo.processIdentifier
        guard let mine = processes.first(where: { $0.pid == me }) else {
            return XCTFail("current process not found in list")
        }
        // The test process's own cwd is readable without sudo.
        let cwd = try XCTUnwrap(mine.workingDirectory, "own process cwd should be readable")
        XCTAssertTrue(cwd.hasPrefix("/"), "cwd should be an absolute path")
        // commandLine is best-effort: if present it must be non-empty (no crash either way).
        if let cmd = mine.commandLine {
            XCTAssertFalse(cmd.isEmpty)
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NativeProviderSmokeTests/testReadsWorkingDirectoryForOwnProcess`
Expected: FAIL — `workingDirectory` is `nil` (provider does not populate it yet).

- [ ] **Step 3: Implement the readers and populate the fields**

In `Sources/MacMemCore/NativeMemoryProvider.swift`:

(a) In `listProcesses()` (lines 17-35), compute the two fields once and pass them into BOTH `ProcessSample(...)` constructions. Replace the closure body (lines 18-34) with:

```swift
            guard pid > 0 else { return nil }
            let path = Self.path(for: pid)
            let parentPID = Self.ppid(for: pid)
            let name = appIdentity[pid]?.name ?? Self.name(for: pid, fallbackPath: path)
            let bundleID = appIdentity[pid]?.bundleID ?? Self.bundleID(forPath: path)
            let cwd = Self.workingDirectory(for: pid)
            let cmd = Self.commandLine(for: pid)

            if let usage = Self.rusage(for: pid) {
                return ProcessSample(pid: pid, ppid: parentPID, responsiblePID: ResponsiblePID.lookup(for: pid, enabled: useResponsiblePID),
                                     bundleID: bundleID, name: name, executablePath: path,
                                     footprintBytes: usage.footprint, residentBytes: usage.resident,
                                     pageIns: usage.pageIns, isReadable: true,
                                     workingDirectory: cwd, commandLine: cmd)
            } else {
                // Not owned by us / not permitted: still list it, marked unreadable.
                return ProcessSample(pid: pid, ppid: parentPID, responsiblePID: ResponsiblePID.lookup(for: pid, enabled: useResponsiblePID),
                                     bundleID: bundleID, name: name, executablePath: path,
                                     footprintBytes: 0, residentBytes: 0, pageIns: 0, isReadable: false,
                                     workingDirectory: cwd, commandLine: cmd)
            }
```

(b) Add the two reader functions. Insert them right after `path(for:)` (after line 88):

```swift
    // PROC_PIDVNODEPATHINFO == 9 (sys/proc_info.h). Hardcoded for the same macOS-26 Swift
    // overlay reason documented above for PROC_PIDPATHINFO_MAXSIZE.
    private static let procPIDVnodePathInfo: Int32 = 9

    /// Best-effort current working directory for `pid`. Readable for processes owned by the
    /// current user (or any process when running as root); `nil` otherwise or on any error.
    private static func workingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let rc = proc_pidinfo(pid, procPIDVnodePathInfo, 0, &info, size)
        guard rc == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        return path.isEmpty ? nil : path
    }

    // KERN_PROCARGS2 == 49 (sys/sysctl.h). Hardcoded for the same macOS-26 overlay reason.
    private static let kernProcArgs2: Int32 = 49

    /// Best-effort process arguments after the executable path, space-joined and trimmed.
    /// Reads the KERN_PROCARGS2 blob: [int argc][exec_path NUL][argv0 NUL]...[argv NUL]...
    /// Returns `nil` when unreadable (other users' processes) or when there are no args.
    private static func commandLine(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, kernProcArgs2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) {
            $0.copyBytes(from: buffer[0..<MemoryLayout<Int32>.size])
        }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        // Skip the executable path string.
        while index < size && buffer[index] != 0 { index += 1 }
        // Skip the NUL padding between exec path and argv[0].
        while index < size && buffer[index] == 0 { index += 1 }

        // Read argc NUL-terminated argument strings.
        var args: [String] = []
        var current: [UInt8] = []
        while index < size && args.count < Int(argc) {
            let byte = buffer[index]
            if byte == 0 {
                args.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
            index += 1
        }

        guard !args.isEmpty else { return nil }
        // args[0] is argv[0] (the command as invoked); the label wants everything after it.
        let rest = args.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
```

- [ ] **Step 4: Run the smoke test to verify it passes**

Run: `swift test --filter NativeProviderSmokeTests`
Expected: PASS — own-process cwd is non-nil and absolute. (If a future sandbox denies vnode info, the test would fail loudly; that is acceptable signal, not silent degradation.)

- [ ] **Step 5: Commit**

```bash
git add Sources/MacMemCore/NativeMemoryProvider.swift Tests/MacMemCoreTests/NativeProviderSmokeTests.swift
git commit -m "$(cat <<'EOF'
feat: read working directory and argv natively per process

proc_pidinfo(PROC_PIDVNODEPATHINFO) for cwd and sysctl(KERN_PROCARGS2)
for argv, both best-effort (nil for other users' processes without sudo).
Constants hardcoded per the macOS-26 Swift-overlay pattern already used
for PROC_PIDPATHINFO_MAXSIZE.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `--full-paths` CLI flag + README

**Files:**
- Modify: `Sources/macmem/main.swift:30-31,69-70`
- Modify: `README.md:48-59`

- [ ] **Step 1: Add the flag and thread it into `build`**

In `Sources/macmem/main.swift`, add the flag after the `browser` option (after line 31):

```swift
    @Flag(name: .long, help: "Show full working-directory paths in CLI process labels instead of the shortest unique suffix.")
    var fullPaths = false
```

Then update the `build` call in `printOnce` (lines 69-70):

```swift
        let snapshot = SnapshotBuilder(provider: provider, tabSource: tabSource)
            .build(topN: top, includeTabs: !noTabs, includeSwap: !noSwap,
                   pathStyle: fullPaths ? .fullPath : .shortestUnique)
```

- [ ] **Step 2: Build and smoke-test the flag manually**

Run: `swift build && swift run macmem --full-paths --no-tabs --top 5`
Expected: builds and runs; bundle-less CLI rows (if any) show full `~/…` paths. `swift run macmem --help` lists `--full-paths`.

- [ ] **Step 3: Document the flag in the README**

In `README.md`, add a line to the Usage code block (after the `--browser` line, line 57):

```bash
macmem --full-paths          # show full working-directory paths in CLI process labels (default: shortest unique suffix)
```

- [ ] **Step 4: Run the full suite**

Run: `swift test`
Expected: PASS (no test depends on the CLI flag wiring directly; behavior is covered at the `SnapshotBuilder`/`AppGrouper` layer).

- [ ] **Step 5: Commit**

```bash
git add Sources/macmem/main.swift README.md
git commit -m "$(cat <<'EOF'
feat: add --full-paths CLI flag for CLI process labels

Toggles bundle-less CLI labels between the shortest-unique directory
suffix (default) and the full ~-abbreviated path. Documented in README.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full suite and CI mirror**

Run: `just ci`
Expected: clean release build + full XCTest suite, all green.

- [ ] **Step 2: Manual end-to-end smoke against live processes**

Run: `swift run macmem --top 10 --no-tabs`
Expected: bundle-less CLI groups (e.g. `make`, `node`) show `name — <dir> (<argv>)` labels; same name in different directories appears as separate rows; long labels are middle-truncated with the trailing argv token preserved; bundle-ID apps (browsers, editors) keep their plain names.

- [ ] **Step 3: Verify the SWAP section inherits labels**

Run: `swift run macmem --top 10 --no-tabs` (review the "Compressed memory per app" block)
Expected: the compressed-memory rows carry the same directory-aware labels as TOP APPS (single labeling site confirmed end-to-end).

---

## Self-Review

**1. Spec coverage:**
- Decision 1 (split by directory) → Task 3 (`groupKey` `(name, cwd)`, `testBundlelessSameNameDifferentCwdSplits` / `...SameCwdMerges`). ✓
- Decision 2 (cwd-unreadable → bare-name collapse) → Task 3 (`collapsedLabel`, `testBundlelessNilCwdCollapsesToBareName`). ✓
- Decision 3 (shortest unique suffix, min 1) → Task 2 (`shortestUniqueSuffixes` + tiebreak tests). ✓
- Decision 4 (`--full-paths`) → Task 7 + threading in Tasks 5/3. ✓
- Data Captured (`workingDirectory`, `commandLine`, default nil, native readers, raw argv) → Tasks 1 + 6. ✓
- Identity & Label Logic (ProcessLabel API, suffix timing before topN) → Tasks 2 + 3. ✓
- Single labeling site (aggregator inherits) → unchanged aggregator; verified in Task 8 Step 3. ✓
- Renderer Impact (auto-size + middle-truncate, only TOP APPS, degenerate case) → Task 4. ✓
- Error handling (nil on failure, no sudo demand) → Task 6 readers return nil; Task 3 collapse path. ✓
- Testing section (ProcessLabel/Renderer/AppGrouper/SnapshotBuilder/native smoke) → Tasks 2,4,3,5,6. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows complete code. ✓

**3. Type consistency:**
- `ProcessLabel.groupKey(name:baseBundleID:workingDirectory:)`, `shortestUniqueSuffixes(_:)`, `abbreviateHome(_:home:)`, `displayLabel(name:dirDisplay:commandLine:)`, `collapsedLabel(name:processCount:)` — identical signatures across Tasks 2 and 3. ✓
- `PathStyle` cases `.shortestUnique` / `.fullPath` — consistent across Tasks 2, 3, 5, 7. ✓
- `AppGrouper.group(_:topN:pathStyle:homeDirectory:)` — defined Task 3, called with defaults in existing tests, with `pathStyle` in Task 5. ✓
- `TextRenderer.middleTruncate(_:width:)` `internal static` — defined Task 4, called in Task 4 tests. ✓
- `ProcessSample.init(..., workingDirectory:commandLine:)` defaults — Task 1; new call sites in Task 6 pass both. ✓

No gaps found.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-07-cli-process-labels.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, spec + code-quality review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session with checkpoints for review.

Which approach?
