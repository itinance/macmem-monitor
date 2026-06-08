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
    /// Fired with `true` when a sampling cycle starts and `false` when it ends, so the
    /// UI can show a subtle "refreshing" cue without blocking interaction.
    public var onRefreshChange: ((Bool) -> Void)?
    /// Fired with `true` while the FIRST browser-tab enumeration is in flight (when no
    /// tabs are cached yet) and `false` once it completes. Lets the tabs section show a
    /// "reading tabs…" spinner instead of a misleading "no tabs" on first open.
    public var onTabsLoadingChange: ((Bool) -> Void)?

    private var timer: Timer?

    /// Guards against overlapping cycles: tab enumeration over a browser with hundreds
    /// of tabs can outlast the open-mode interval, and without this the timer would pile
    /// heavy builds on top of each other and make the menu feel unresponsive.
    private var ticking = false

    /// Last-known browser tabs, refreshed on a slower cadence than apps/swap (tab
    /// enumeration is the expensive part). Spliced into the fast snapshots so the tabs
    /// section never blanks between refreshes.
    private var cachedBrowsers: [BrowserMemory] = []
    private var cachedTabsStatus: SectionStatus
    private var lastTabFetch: Date?

    /// Poll intervals (seconds): slow while collapsed, faster while open.
    private let collapsedInterval: TimeInterval = 5.0
    private let openInterval: TimeInterval = 2.5
    /// Browser tabs change slowly and are costly to read, so refresh them at most this
    /// often (vs. apps/swap/pressure which refresh every `openInterval`).
    private let tabInterval: TimeInterval = 15.0

    public var currentInterval: TimeInterval {
        mode == .open ? openInterval : collapsedInterval
    }

    public init(provider: MemoryProvider, tabSource: TabSource?, topN: Int) {
        self.provider = provider
        self.tabSource = tabSource
        self.topN = topN
        // With no tab source the tabs section needs the permission banner from the start;
        // with one, default to .ok and let the first real fetch replace it.
        self.cachedTabsStatus = tabSource == nil ? .permissionNeeded : .ok
    }

    /// Reschedule the timer at the current interval and tick once immediately so the
    /// UI reflects the new mode without waiting a full interval.
    private func scheduleAndTickNow() {
        scheduleTimer()
        Task { await tick() }
    }

    /// Switch modes, reschedule the timer at the new interval, and tick once now
    /// so the UI updates immediately on open/close instead of after a full delay.
    public func setMenuOpen(_ open: Bool) {
        mode = open ? .open : .collapsed
        scheduleAndTickNow()
    }

    /// Switch modes without triggering an immediate tick. Intended for tests
    /// that want deterministic call-count assertions: using this avoids the
    /// fire-and-forget `Task { await tick() }` that `setMenuOpen` spawns, which
    /// would otherwise race with the test's own explicit `await engine.tick()`.
    ///
    /// Production code should use `setMenuOpen(_:)` so the UI updates immediately.
    func setMode(_ newMode: Mode) {
        mode = newMode
        scheduleTimer()
    }

    /// Start sampling (called once when the app launches).
    public func start() {
        scheduleAndTickNow()
    }

    public func stop() {
        timer?.invalidate(); timer = nil
    }

    /// One sampling cycle. Always refreshes pressure (cheap). In open mode it delivers
    /// a fast snapshot first (apps/swap/compressed, no tab enumeration) so the menu
    /// paints quickly, then refreshes the slow browser tabs only when they're due.
    /// Overlapping cycles are skipped so heavy builds never pile up.
    public func tick() async {
        let p = provider.pressure()
        onPressure?(p)
        guard mode == .open else { return }
        guard !ticking else { return }
        ticking = true
        onRefreshChange?(true)
        defer { ticking = false; onRefreshChange?(false) }

        let provider = self.provider
        let tabSource = self.tabSource
        let topN = self.topN

        // Phase 1 — fast snapshot WITHOUT browser-tab enumeration, so apps/swap/pressure
        // paint in ~1.5s. The last-known tabs are spliced in so the tabs section persists.
        let fast = await Task.detached(priority: .userInitiated) {
            SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: topN, includeTabs: false)
        }.value
        onSnapshot?(withCachedTabs(fast))

        // Phase 2 — refresh browser tabs only when there's a source and they're due.
        // Enumerating hundreds of tabs takes seconds, so this runs on open and then at
        // most every `tabInterval`, never on every open-mode tick.
        guard tabSource != nil, shouldRefreshTabs() else { return }
        let firstLoad = cachedBrowsers.isEmpty
        if firstLoad { onTabsLoadingChange?(true) }
        let full = await Task.detached(priority: .utility) {
            SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: topN, includeTabs: true)
        }.value
        cachedBrowsers = full.browsers
        cachedTabsStatus = full.tabsStatus
        lastTabFetch = Date()
        if firstLoad { onTabsLoadingChange?(false) }
        onSnapshot?(full)
    }

    private func shouldRefreshTabs() -> Bool {
        guard let last = lastTabFetch else { return true }
        return Date().timeIntervalSince(last) >= tabInterval
    }

    /// Returns `fast` with its (empty) tabs replaced by the last-known browser tabs, so
    /// the tabs section keeps showing real data between the slower tab refreshes.
    private func withCachedTabs(_ fast: MemorySnapshot) -> MemorySnapshot {
        MemorySnapshot(topApps: fast.topApps, appsStatus: fast.appsStatus,
                       unreadableProcessCount: fast.unreadableProcessCount,
                       swap: fast.swap, compressedUsers: fast.compressedUsers,
                       compressedUnreadableCount: fast.compressedUnreadableCount,
                       compressedAvailable: fast.compressedAvailable,
                       swapStatus: fast.swapStatus,
                       browsers: cachedBrowsers, tabsStatus: cachedTabsStatus)
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
