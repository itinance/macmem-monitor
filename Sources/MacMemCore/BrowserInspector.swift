import Foundation

/// Pairs each running browser's open tabs with its MEASURED total process memory.
///
/// Per-tab memory is deliberately NOT reported: no browser's automation API
/// exposes it (the `tab` object carries only id/title/URL/loading, and no public
/// API maps a renderer/WebContent PID to a URL). Pairing renderer footprints to
/// tabs by size — as an earlier version did — produces a plausible-but-false
/// number, so we drop it. Instead each browser shows one real aggregate total
/// (from `SnapshotBuilder.browserTotals`) with its tabs listed underneath.
public struct BrowserInspector {
    let source: TabSource
    public init(source: TabSource) { self.source = source }

    /// Build one `BrowserMemory` per running browser.
    ///
    /// - Parameters:
    ///   - browserTotals: measured `(bytes, count)` per browser display name. `bytes`
    ///     is nil when the browser's memory is not honestly attributable (Safari without
    ///     `--responsible-pid`); a missing key also yields a nil total.
    ///   - hadErrors: set to `true` if at least one browser's tab fetch failed; left
    ///     untouched when all browsers succeed. The caller uses this to set `.partial`
    ///     status while still returning the browsers that did succeed.
    public func browsers(browserTotals: [String: (bytes: UInt64?, count: Int)] = [:],
                         hadErrors: inout Bool) -> [BrowserMemory] {
        var result: [BrowserMemory] = []
        for browser in source.runningBrowsers() {
            do {
                let raw = try source.tabs(for: browser)
                let tabs = raw.map { BrowserTab(title: $0.title, url: $0.url) }
                let info = browserTotals[browser]
                result.append(BrowserMemory(browser: browser,
                                            totalFootprintBytes: info?.bytes,
                                            processCount: info?.count ?? 0,
                                            tabs: tabs))
            } catch {
                // One browser failed — record the signal and continue with the others.
                hadErrors = true
            }
        }
        return result
    }
}
