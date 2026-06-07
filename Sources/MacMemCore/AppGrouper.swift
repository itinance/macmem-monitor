import Foundation

/// Collapses helper/renderer processes into their owning application.
///
/// Strategy (layered): the *preferred* signal is the responsible PID
/// (see `ResponsiblePID.swift` — a private API, default-off). The always-available
/// public fallback groups by base bundle identifier (helper suffixes stripped),
/// then by cleaned process name.
public struct AppGrouper {
    public init() {}

    private struct Owner {
        let name: String
        let bundleID: String?
        let workingDirectory: String?
        let commandLine: String?
    }

    private struct Acc {
        var name: String
        var bundleID: String?
        var workingDirectory: String?
        var commandLine: String?   // representative: argv of the highest-footprint member
        var repFootprint: UInt64
        var total: UInt64
        var pids: [Int32]
    }

    public func group(_ samples: [ProcessSample], topN: Int = 10,
                      pathStyle: PathStyle = .shortestUnique,
                      homeDirectory: String = NSHomeDirectory()) -> [AppGroup] {
        let limit = max(0, topN)
        let byPID = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        var groups: [String: Acc] = [:]
        for s in samples {
            let owner = resolveOwner(s, byPID: byPID)
            let key = ProcessLabel.groupKey(name: owner.name, baseBundleID: owner.bundleID,
                                            workingDirectory: owner.workingDirectory)
            if var acc = groups[key] {
                acc.total += s.footprintBytes
                acc.pids.append(s.pid)
                // Strict >: on an exact footprint tie the first-seen process keeps its argv as representative.
                if s.footprintBytes > acc.repFootprint {
                    acc.repFootprint = s.footprintBytes
                    acc.commandLine = owner.commandLine
                }
                groups[key] = acc
            } else {
                groups[key] = Acc(name: owner.name, bundleID: owner.bundleID,
                                  workingDirectory: owner.workingDirectory,
                                  commandLine: owner.commandLine,
                                  repFootprint: s.footprintBytes,
                                  total: s.footprintBytes, pids: [s.pid])
            }
        }

        // Shortest-unique suffixes per same-name cohort of bundle-less directory groups.
        // Computed over ALL such groups (before the topN cut) so labels stay stable
        // regardless of truncation and across the TOP APPS / SWAP sections.
        let dirAccs = groups.values.filter { $0.bundleID == nil && $0.workingDirectory != nil }
        var suffixesByName: [String: [String: String]] = [:]
        for (name, accs) in Dictionary(grouping: dirAccs, by: { $0.name }) {
            let paths = accs.compactMap { $0.workingDirectory }
            suffixesByName[name] = ProcessLabel.shortestUniqueSuffixes(paths)
        }

        return groups.values
            .map { acc -> AppGroup in
                let display = displayName(for: acc, pathStyle: pathStyle,
                                          home: homeDirectory, suffixesByName: suffixesByName)
                return AppGroup(name: display, bundleID: acc.bundleID,
                                totalFootprintBytes: acc.total,
                                processCount: acc.pids.count, pids: acc.pids.sorted())
            }
            .sorted { $0.totalFootprintBytes > $1.totalFootprintBytes }
            .prefix(limit)
            .map { $0 }
    }

    private func displayName(for acc: Acc, pathStyle: PathStyle, home: String,
                             suffixesByName: [String: [String: String]]) -> String {
        // App with a bundle ID: keep its current name unchanged.
        if acc.bundleID != nil { return acc.name }
        // Bundle-less with a readable cwd: directory-aware label.
        if let cwd = acc.workingDirectory {
            let dirDisplay: String
            switch pathStyle {
            case .fullPath:
                dirDisplay = ProcessLabel.abbreviateHome(cwd, home: home)
            case .shortestUnique:
                dirDisplay = suffixesByName[acc.name]?[cwd]
                    ?? ProcessLabel.abbreviateHome(cwd, home: home)
            }
            return ProcessLabel.displayLabel(name: acc.name, dirDisplay: dirDisplay,
                                             commandLine: acc.commandLine)
        }
        // Bundle-less, cwd unreadable: collapsed bare-name row.
        return ProcessLabel.collapsedLabel(name: acc.name, processCount: acc.pids.count)
    }

    private func resolveOwner(_ s: ProcessSample, byPID: [Int32: ProcessSample],
                              visited: Set<Int32> = []) -> Owner {
        var visited = visited
        guard visited.insert(s.pid).inserted else {
            return terminalOwner(s)
        }
        // Step 1: responsiblePID (highest-fidelity signal, requires private API/entitlement).
        if let rpid = s.responsiblePID, rpid != s.pid, let owner = byPID[rpid] {
            return resolveOwner(owner, byPID: byPID, visited: visited)
        }
        // Step 2: process has its own bundle ID → it is an app. Keep its identity.
        if s.bundleID != nil {
            return terminalOwner(s)
        }
        // Step 3: PPID fallback — fold bundle-less children into a launching *app* parent.
        if s.ppid > 1, let parent = byPID[s.ppid], parent.bundleID != nil {
            return resolveOwner(parent, byPID: byPID, visited: visited)
        }
        // Step 4: no usable owner signal — return the process under its own name.
        return terminalOwner(s)
    }

    /// The owner is the process itself. Apps carry no cwd/argv; bundle-less CLI
    /// processes carry theirs so the label can disambiguate them.
    private func terminalOwner(_ s: ProcessSample) -> Owner {
        if let bundleID = s.bundleID {
            return Owner(name: Self.cleanName(s.name), bundleID: Self.baseBundleID(bundleID),
                         workingDirectory: nil, commandLine: nil)
        }
        return Owner(name: Self.cleanName(s.name), bundleID: nil,
                     workingDirectory: s.workingDirectory, commandLine: s.commandLine)
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
