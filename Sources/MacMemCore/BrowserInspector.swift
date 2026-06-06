import Foundation

/// Turns raw browser tabs into `BrowserTab`s. Per-tab memory is a heuristic:
/// when a browser's renderer-process count equals its tab count, we pair
/// renderer footprints (largest → largest) to tabs. Any mismatch leaves the
/// estimate blank, per the spec's "leave blank when ambiguous" rule.
public struct BrowserInspector {
    let source: TabSource
    public init(source: TabSource) { self.source = source }

    /// Collect tabs from all running browsers.
    ///
    /// - Parameters:
    ///   - rendererFootprintsByBrowser: per-renderer footprints keyed by browser display name.
    ///   - topN: maximum number of tabs to return.
    ///   - hadErrors: set to `true` if at least one browser's tab fetch failed; untouched
    ///     when all browsers succeed. The caller uses this to set `.partial` status while
    ///     still returning the tabs that did succeed.
    public func topTabs(rendererFootprintsByBrowser: [String: [UInt64]] = [:],
                        topN: Int = 10,
                        hadErrors: inout Bool) -> [BrowserTab] {
        var all: [BrowserTab] = []

        for browser in source.runningBrowsers() {
            do {
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
            } catch {
                // One browser failed — record the error signal and continue with others.
                hadErrors = true
            }
        }

        // Heaviest first when estimates exist; tabs without estimates sort last.
        return all
            .sorted { ($0.estimatedBytes ?? 0) > ($1.estimatedBytes ?? 0) }
            .prefix(topN)
            .map { $0 }
    }
}
