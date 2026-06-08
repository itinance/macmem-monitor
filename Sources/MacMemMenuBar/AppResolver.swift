import Foundation
import MacMemCore

/// A running application reduced to the only fields needed to match it against
/// an `AppGroup`. Keeping this a plain value (not `NSRunningApplication`) makes
/// the matching logic pure and unit-testable.
public struct AppCandidate: Equatable {
    public let bundleID: String?
    public let pid: Int32
    public init(bundleID: String?, pid: Int32) {
        self.bundleID = bundleID; self.pid = pid
    }
}

/// Pure logic for resolving which running app an `AppGroup` refers to.
public enum AppResolver {
    /// Returns the running candidate the group refers to, or nil.
    /// Prefers a bundle-id match; falls back to a candidate whose pid is in the group.
    public static func match(group: AppGroup, candidates: [AppCandidate]) -> AppCandidate? {
        if let bundle = group.bundleID,
           let c = candidates.first(where: { $0.bundleID == bundle }) {
            return c
        }
        let groupPIDs = Set(group.pids)
        return candidates.first(where: { groupPIDs.contains($0.pid) })
    }
}
