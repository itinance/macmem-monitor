import Foundation

/// Aggregates MEASURED per-app compressed memory into per-app totals and ranks them.
/// This is not an estimate: it sums CMPRS values from top(1) across each app's processes.
/// Processes whose compressed footprint could not be measured contribute nothing.
/// Groups whose measured total is zero are excluded.
public struct CompressedMemoryAggregator {
    public init() {}

    public func entries(groups: [AppGroup], compressedByPID: [pid_t: UInt64], topN: Int = 10) -> [CompressedMemoryEntry] {
        let limit = max(0, topN)
        let scored: [(group: AppGroup, total: UInt64)] = groups.compactMap { g in
            let total = g.pids.reduce(UInt64(0)) { $0 + (compressedByPID[$1] ?? 0) }
            return total > 0 ? (g, total) : nil
        }
        return scored
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { CompressedMemoryEntry(appName: $0.group.name, bundleID: $0.group.bundleID, compressedBytes: $0.total) }
    }
}
