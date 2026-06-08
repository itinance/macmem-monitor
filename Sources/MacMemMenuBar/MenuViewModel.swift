import Foundation
import MacMemCore

/// A staged, user-confirmable action. Equatable so the view can drive a
/// `.confirmationDialog` and tests can assert the state machine.
public enum PendingConfirmation: Equatable {
    case quit(AppGroup)
    case purge
}

/// Single source of truth for the menubar UI. `ObservableObject` (not `@Observable`)
/// to keep the macOS 13 deployment target. All system effects go through `SystemActions`.
@MainActor
public final class MenuViewModel: ObservableObject {
    @Published public private(set) var pressure: MemoryPressure = .unknown
    @Published public private(set) var snapshot: MemorySnapshot?
    @Published public private(set) var lastUpdated: Date?
    @Published public var pendingConfirmation: PendingConfirmation?
    @Published public private(set) var lastActionMessage: String?

    private let engine: SnapshotEngine
    private let actions: SystemActions

    public init(provider: MemoryProvider, tabSource: TabSource?,
                actions: SystemActions, topN: Int = 10) {
        self.actions = actions
        self.engine = SnapshotEngine(provider: provider, tabSource: tabSource, topN: topN)
        self.engine.onPressure = { [weak self] in self?.pressure = $0 }
        self.engine.onSnapshot = { [weak self] snap in
            self?.snapshot = snap
            self?.lastUpdated = Date()
        }
    }

    // MARK: Lifecycle
    public func start() { engine.start() }
    public func setMenuOpen(_ open: Bool) { engine.setMenuOpen(open) }
    /// Forces one immediate sampling cycle (used by tests and manual refresh).
    public func refreshNow() async { await engine.tick() }

    // MARK: Intents
    public func requestQuit(_ app: AppGroup) { pendingConfirmation = .quit(app) }
    public func requestPurge() { pendingConfirmation = .purge }
    public func cancelPending() { pendingConfirmation = nil }

    public func confirmPending() async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        let result: ActionResult
        switch pending {
        case .quit(let app): result = await actions.quit(app: app)
        case .purge:         result = await actions.purge()
        }
        applyResult(result)
    }

    public func reveal(_ app: AppGroup) { actions.revealInActivityMonitor(app: app) }

    public func copySnapshot() {
        guard let snapshot else { return }
        actions.copySnapshot(TextRenderer.render(snapshot))
    }

    private func applyResult(_ result: ActionResult) {
        switch result {
        case .ok, .cancelled: lastActionMessage = nil
        case .failed(let msg): lastActionMessage = msg
        case .notPermitted:    lastActionMessage = "Not permitted."
        }
    }
}
