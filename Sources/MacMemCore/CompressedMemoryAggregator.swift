import Foundation

/// Aggregates MEASURED per-process compressed memory into per-app totals and ranks them.
/// This is not an estimate: it sums task_info(TASK_VM_INFO).compressed across each app's
/// processes. Processes whose compressed footprint could not be measured (nil) contribute
/// nothing. Groups whose measured total is zero are excluded.
public struct CompressedMemoryAggregator {
    public init() {}

    public func entries(groups: [AppGroup], samples: [ProcessSample], topN: Int = 10) -> [CompressedMemoryEntry] {
        let limit = max(0, topN)
        // First-wins dedup handles transient duplicate PIDs that proc_listpids may return.
        let compressedByPID = Dictionary(
            samples.compactMap { s in s.compressedBytes.map { (s.pid, $0) } },
            uniquingKeysWith: { a, _ in a })

        let scored: [(group: AppGroup, total: UInt64)] = groups.compactMap { g in
            let total = g.pids.reduce(UInt64(0)) { $0 + (compressedByPID[$1] ?? 0) }
            return total > 0 ? (g, total) : nil
        }

        return scored
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { CompressedMemoryEntry(appName: $0.group.name, bundleID: $0.group.bundleID,
                                         compressedBytes: $0.total) }
    }
}
