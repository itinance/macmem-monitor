import Foundation
import MacMemCore

/// Outcome of a user-triggered action.
public enum ActionResult: Equatable, Sendable {
    case ok
    case cancelled
    case failed(String)
    case notPermitted
}

/// All side-effecting operations the menubar app can perform, behind a seam so
/// the view model stays pure and tests use a fake (no real terminate/purge).
@MainActor public protocol SystemActions {
    func quit(app: AppGroup) async -> ActionResult
    func purge() async -> ActionResult
    func copySnapshot(_ text: String)
}

/// Records calls and returns scripted results. Reference type so tests can
/// inspect it after passing it into a view model.
public final class FakeSystemActions: SystemActions {
    public var quitResult: ActionResult = .ok
    public var purgeResult: ActionResult = .ok
    public private(set) var quitCalls: [AppGroup] = []
    public private(set) var purgeCallCount = 0
    public private(set) var copiedText: String?

    public init() {}

    public func quit(app: AppGroup) async -> ActionResult {
        quitCalls.append(app); return quitResult
    }
    public func purge() async -> ActionResult {
        purgeCallCount += 1; return purgeResult
    }
    public func copySnapshot(_ text: String) { copiedText = text }
}
