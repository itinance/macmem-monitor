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
