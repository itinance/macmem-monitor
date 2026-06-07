import Foundation

/// Orchestrates provider + grouper + estimator + inspector into one snapshot.
/// Each section is computed independently inside its own do/catch so a failure
/// in one never fails the others.
public struct SnapshotBuilder {
    let provider: MemoryProvider
    let tabSource: TabSource?
    let knownBrowsers: Set<String>

    public init(provider: MemoryProvider, tabSource: TabSource?,
                knownBrowsers: Set<String> = Set(SupportedBrowsers.all)) {
        self.provider = provider
        self.tabSource = tabSource
        self.knownBrowsers = knownBrowsers
    }

    public func build(topN: Int = 10, includeTabs: Bool = true, includeSwap: Bool = true,
                      pathStyle: PathStyle = .shortestUnique) -> MemorySnapshot {
        // --- Apps section ---
        // Group ALL readable processes once, then slice the top N for the apps list.
        // The full (un-truncated) grouping is reused by the tabs section so a browser
        // ranked outside topN still gets its real total — no second grouping pass.
        var topApps: [AppGroup] = []
        var allGroups: [AppGroup] = []
        var appsStatus: SectionStatus = .ok
        var unreadable = 0
        var samples: [ProcessSample] = []
        do {
            samples = try provider.listProcesses()
            unreadable = samples.filter { !$0.isReadable }.count
            let readable = samples.filter { $0.isReadable }
            allGroups = AppGrouper().group(readable, topN: readable.count, pathStyle: pathStyle)
            topApps = Array(allGroups.prefix(max(0, topN)))
            appsStatus = unreadable > 0 ? .partial : .ok
        } catch {
            appsStatus = .error
        }

        // --- Swap totals + measured compressed memory ---
        var swap: SwapInfo?
        var compressedUsers: [CompressedMemoryEntry] = []
        var compressedMissing = 0
        var compressedAvailable = true   // neutral default when --no-swap skips this block
        var swapStatus: SectionStatus = .ok
        if includeSwap {
            do {
                swap = try provider.readSwap()
            } catch {
                swapStatus = .error
            }
            let compressedMap = (try? provider.compressedByPID()) ?? [:]
            compressedAvailable = !compressedMap.isEmpty
            compressedUsers = CompressedMemoryAggregator().entries(groups: topApps, compressedByPID: compressedMap, topN: topN)
            // Only count per-pid misses when top actually succeeded; if it failed entirely
            // (empty map) we already signal that via compressedAvailable = false.
            let shownPIDs = Set(topApps.flatMap { $0.pids })
            compressedMissing = compressedAvailable ? shownPIDs.filter { compressedMap[$0] == nil }.count : 0
        }

        // --- Tabs section ---
        var browsers: [BrowserMemory] = []
        var tabsStatus: SectionStatus = .ok
        if includeTabs {
            if let tabSource {
                let totals = browserTotals(allGroups: allGroups, from: samples)
                var hadBrowserErrors = false
                browsers = BrowserInspector(source: tabSource)
                    .browsers(browserTotals: totals, hadErrors: &hadBrowserErrors)
                // .ok only when every browser succeeded; .partial when some failed.
                tabsStatus = hadBrowserErrors ? .partial : .ok
            } else {
                tabsStatus = .permissionNeeded
            }
        }

        return MemorySnapshot(topApps: topApps, appsStatus: appsStatus,
                              unreadableProcessCount: unreadable, swap: swap,
                              compressedUsers: compressedUsers,
                              compressedUnreadableCount: compressedMissing,
                              compressedAvailable: compressedAvailable,
                              swapStatus: swapStatus,
                              browsers: browsers, tabsStatus: tabsStatus)
    }

    /// MEASURED total footprint + process count per browser, keyed by display name.
    ///
    /// Derived from `allGroups`, the full (un-truncated) grouping computed once in
    /// `build()`, so a browser ranked outside the TOP APPS topN still gets its real
    /// total without a second grouping pass. A browser's processes fold into a single
    /// AppGroup named after the browser — Chromium families (Brave, Chrome, Edge) by
    /// base bundle id — so `group.totalFootprintBytes` IS the whole-browser total.
    /// This is the same measured figure shown in TOP APPS, never an estimate.
    ///
    /// Safari is the documented exception. Its WebKit content processes live in the
    /// system WebKit framework (`com.apple.WebKit.WebContent`), are shared across all
    /// WebKit apps, and only fold into the "Safari" group under `--responsible-pid`.
    /// When such content processes exist outside the Safari group, Safari's total is
    /// reported as nil so the renderer states the limitation rather than printing a
    /// misleadingly small number (just the main Safari process).
    func browserTotals(allGroups: [AppGroup],
                       from samples: [ProcessSample]) -> [String: (bytes: UInt64?, count: Int)] {
        let groupByName = Dictionary(allGroups.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let webContentPIDs = Set(samples
            .filter { $0.isReadable && $0.bundleID == "com.apple.WebKit.WebContent" }
            .map { $0.pid })

        var result: [String: (bytes: UInt64?, count: Int)] = [:]
        for browser in knownBrowsers {
            let group = groupByName[browser]
            if browser == "Safari" {
                // WebKit content not folded into the Safari group is system-shared
                // and not honestly attributable to Safari.
                let unattributed = webContentPIDs.subtracting(Set(group?.pids ?? []))
                if !unattributed.isEmpty {
                    result[browser] = (nil, group?.processCount ?? 0)
                    continue
                }
            }
            if let group {
                result[browser] = (group.totalFootprintBytes, group.processCount)
            }
        }
        return result
    }
}

/// Returns the process exit code for the given snapshot.
///
/// Exits non-zero only when BOTH the apps section AND the swap section are `.error`,
/// meaning the core memory provider fundamentally failed. Tabs failing alone is not fatal.
/// Partial results (`.partial`, `.permissionNeeded`) still exit 0.
public func snapshotExitCode(_ snapshot: MemorySnapshot) -> Int32 {
    if snapshot.appsStatus == .error && snapshot.swapStatus == .error {
        return 1
    }
    return 0
}
