import Foundation

/// Ranks likely swap contributors. NOTE: `pageIns` is a *noisy* proxy — it
/// counts file + anonymous page-ins, not swap-ins specifically. The whole
/// section is therefore an estimate and is always confidence-labeled.
public struct SwapEstimator {
    public init() {}

    public func culprits(groups: [AppGroup], samples: [ProcessSample],
                         swap: SwapInfo, topN: Int = 10) -> [SwapCulprit] {
        guard swap.usedBytes > 0 else { return [] }

        let pageInsByPID = Dictionary(samples.map { ($0.pid, $0.pageIns) },
                                      uniquingKeysWith: { a, _ in a })
        let scored: [(group: AppGroup, score: Double)] = groups.compactMap { g in
            let total = g.pids.reduce(0.0) { $0 + Double(pageInsByPID[$1] ?? 0) }
            return total > 0 ? (g, total) : nil
        }
        let grandTotal = scored.reduce(0.0) { $0 + $1.score }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(topN)
            .map { entry in
                let share = grandTotal > 0 ? entry.score / grandTotal : 0
                let confidence: Confidence = share > 0.5 ? .high : (share > 0.2 ? .medium : .low)
                return SwapCulprit(appName: entry.group.name, bundleID: entry.group.bundleID,
                                   score: entry.score, confidence: confidence)
            }
    }
}
