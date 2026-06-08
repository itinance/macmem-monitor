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

    private var timer: Timer?

    /// Poll intervals (seconds): slow while collapsed, faster while open.
    private let collapsedInterval: TimeInterval = 5.0
    private let openInterval: TimeInterval = 2.5

    public var currentInterval: TimeInterval {
        mode == .open ? openInterval : collapsedInterval
    }

    public init(provider: MemoryProvider, tabSource: TabSource?, topN: Int) {
        self.provider = provider
        self.tabSource = tabSource
        self.topN = topN
    }

    /// Switch modes, reschedule the timer at the new interval, and tick once now
    /// so the UI updates immediately on open/close instead of after a full delay.
    public func setMenuOpen(_ open: Bool) {
        mode = open ? .open : .collapsed
        scheduleTimer()
        Task { await tick() }
    }

    /// Switch modes without triggering an immediate tick. Intended for tests
    /// that want deterministic call-count assertions: using this avoids the
    /// fire-and-forget `Task { await tick() }` that `setMenuOpen` spawns, which
    /// would otherwise race with the test's own explicit `await engine.tick()`.
    ///
    /// Production code should use `setMenuOpen(_:)` so the UI updates immediately.
    public func setMode(_ newMode: Mode) {
        mode = newMode
        scheduleTimer()
    }

    /// Start sampling (called once when the app launches).
    public func start() {
        scheduleTimer()
        Task { await tick() }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
    }

    /// One sampling cycle. Always refreshes pressure (cheap). In open mode it also
    /// builds the full snapshot off the main thread and delivers it on the main actor.
    public func tick() async {
        let p = provider.pressure()
        onPressure?(p)
        guard mode == .open else { return }
        let provider = self.provider
        let tabSource = self.tabSource
        let topN = self.topN
        let snapshot = await Task.detached(priority: .utility) {
            SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: topN)
        }.value
        onSnapshot?(snapshot)
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
