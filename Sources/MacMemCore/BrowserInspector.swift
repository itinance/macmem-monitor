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
