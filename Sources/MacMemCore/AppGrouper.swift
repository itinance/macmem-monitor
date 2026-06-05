import Foundation

/// Collapses helper/renderer processes into their owning application.
///
/// Strategy (layered): the *preferred* signal is the responsible PID
/// (see `ResponsiblePID.swift` — a private API, default-off). The always-available
/// public fallback groups by base bundle identifier (helper suffixes stripped),
/// then by cleaned process name.
public struct AppGrouper {
    public init() {}

    public func group(_ samples: [ProcessSample], topN: Int = 10) -> [AppGroup] {
        let byPID = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        struct Acc { var name: String; var bundleID: String?; var total: UInt64; var pids: [Int32] }
        var groups: [String: Acc] = [:]

        for s in samples {
            let owner = resolveOwner(s, byPID: byPID, depth: 0)
            let key = owner.bundleID ?? owner.name
            if var acc = groups[key] {
                acc.total += s.footprintBytes
                acc.pids.append(s.pid)
                groups[key] = acc
            } else {
                groups[key] = Acc(name: owner.name, bundleID: owner.bundleID,
                                  total: s.footprintBytes, pids: [s.pid])
            }
        }

        return groups.values
            .map { AppGroup(name: $0.name, bundleID: $0.bundleID,
                            totalFootprintBytes: $0.total,
                            processCount: $0.pids.count, pids: $0.pids.sorted()) }
            .sorted { $0.totalFootprintBytes > $1.totalFootprintBytes }
            .prefix(topN)
            .map { $0 }
    }

    func resolveOwner(_ s: ProcessSample, byPID: [Int32: ProcessSample],
                      depth: Int) -> (name: String, bundleID: String?) {
        if depth < 8, let rpid = s.responsiblePID, rpid != s.pid, let owner = byPID[rpid] {
            return resolveOwner(owner, byPID: byPID, depth: depth + 1)
        }
        return (Self.cleanName(s.name), s.bundleID.map(Self.baseBundleID))
    }

    static func baseBundleID(_ id: String) -> String {
        let suffixes = [".helper.renderer", ".helper.gpu", ".helper.plugin", ".helper"]
        for suffix in suffixes where id.lowercased().hasSuffix(suffix) {
            return String(id.dropLast(suffix.count))
        }
        return id
    }

    static func cleanName(_ name: String) -> String {
        if let range = name.range(of: " Helper") {
            return String(name[..<range.lowerBound])
        }
        return name
    }
}
