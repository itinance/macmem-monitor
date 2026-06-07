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
        var topTabs: [BrowserTab] = []
        var tabsStatus: SectionStatus = .ok
        if includeTabs {
            if let tabSource {
                let footprints = rendererFootprints(from: samples, topApps: topApps)
                var hadBrowserErrors = false
                topTabs = BrowserInspector(source: tabSource)
                    .topTabs(rendererFootprintsByBrowser: footprints, topN: topN,
                             hadErrors: &hadBrowserErrors)
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
                              topTabs: topTabs, tabsStatus: tabsStatus)
    }

    /// Renderer footprints per browser, keyed by the browser's display name.
    ///
    /// Only renderer-helper processes are included — the main browser process, GPU helpers,
    /// plugin helpers etc. are excluded. This ensures the footprint array length can be
    /// compared to the tab count in BrowserInspector.topTabs (which only works when they match).
    ///
    /// Renderer detection rules (verified against live processes on macOS 15):
    ///  • Chromium family (Brave, Chrome, Edge): bundleID ends with ".helper.renderer"
    ///    (case-insensitive), OR process name contains "Helper (Renderer)".
    ///    Confirmed identifiers: "com.brave.Browser.helper.renderer" (Brave),
    ///    "com.google.Chrome.helper.renderer" (Chrome); process names like
    ///    "Brave Browser Helper (Renderer)", "Google Chrome Helper (Renderer)".
    ///  • Safari / WebKit: bundleID == "com.apple.WebKit.WebContent" OR
    ///    name == "com.apple.WebKit.WebContent". Confirmed on this machine.
    ///    NOTE: Safari WebContent processes are NOT grouped under the "Safari" AppGroup
    ///    by AppGrouper (they have their own bundleID), so the Safari case is currently
    ///    unreachable via the group.pids path. Left here for correctness and future use.
    func rendererFootprints(from samples: [ProcessSample], topApps: [AppGroup]) -> [String: [UInt64]] {
        var result: [String: [UInt64]] = [:]
        let pidToSample = Dictionary(samples.map { ($0.pid, $0) },
                                     uniquingKeysWith: { a, _ in a })
        for group in topApps where knownBrowsers.contains(group.name) {
            let footprints = group.pids.compactMap { pid -> UInt64? in
                guard let s = pidToSample[pid], Self.isRendererProcess(s) else { return nil }
                return s.footprintBytes
            }
            result[group.name] = footprints
        }
        return result
    }

    /// Returns true when the given process sample is a browser renderer helper.
    static func isRendererProcess(_ s: ProcessSample) -> Bool {
        // Chromium family: bundleID ends with ".helper.renderer"
        if let bid = s.bundleID, bid.lowercased().hasSuffix(".helper.renderer") { return true }
        // Chromium family: name contains "Helper (Renderer)" (e.g. "Brave Browser Helper (Renderer)")
        if s.name.contains("Helper (Renderer)") { return true }
        // Safari / WebKit WebContent process
        if s.bundleID == "com.apple.WebKit.WebContent" { return true }
        if s.name == "com.apple.WebKit.WebContent" { return true }
        return false
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
