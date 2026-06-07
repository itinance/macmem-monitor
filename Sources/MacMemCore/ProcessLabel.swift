import Foundation

/// How the directory portion of a bundle-less CLI label is rendered.
public enum PathStyle: Sendable {
    /// Fewest trailing path components that stay unique within the same-name cohort.
    case shortestUnique
    /// The full `$HOME`-abbreviated (`~/…`) path.
    case fullPath
}

/// Pure string logic for labeling bundle-less CLI process groups (no I/O).
/// `AppGrouper` orchestrates; this computes group keys and display strings so the
/// logic is unit-testable in isolation.
enum ProcessLabel {

    /// Grouping key for a resolved owner:
    /// - base bundle ID present → that ID (existing app-grouping behavior).
    /// - bundle-less + cwd present → `"name\u{0}cwd"` (split per directory).
    /// - bundle-less + cwd nil → `name` (collapse all unreadable same-name processes).
    /// NUL (`\u{0}`) is illegal in POSIX paths and kernel-supplied process names, so it cannot appear in either argument.
    static func groupKey(name: String, baseBundleID: String?, workingDirectory: String?) -> String {
        if let bundleID = baseBundleID { return bundleID }
        if let cwd = workingDirectory { return "\(name)\u{0}\(cwd)" }
        return name
    }

    /// Per-cwd shortest trailing path-component suffix (minimum 1 component) that is
    /// unique within the cohort. A cwd that no trailing suffix can separate from another
    /// (its components are a suffix of the other's) is omitted from the result; the
    /// caller falls back to the full `~`-abbreviated path for those, keeping rows distinct.
    static func shortestUniqueSuffixes(_ paths: [String]) -> [String: String] {
        let componentsByPath: [String: [String]] = Dictionary(
            paths.map { ($0, $0.split(separator: "/").map(String.init)) },
            uniquingKeysWith: { first, _ in first })
        var result: [String: String] = [:]
        for path in paths {
            guard let mine = componentsByPath[path], !mine.isEmpty else { continue }
            for depth in 1...mine.count {
                let suffix = mine.suffix(depth).joined(separator: "/")
                let collides = paths.contains { other in
                    other != path
                        && componentsByPath[other]?.suffix(depth).joined(separator: "/") == suffix
                }
                if !collides {
                    result[path] = suffix
                    break
                }
            }
        }
        return result
    }

    /// Replaces a leading `home` path with `~`.
    /// - Parameter home: an absolute path WITHOUT a trailing slash (`NSHomeDirectory()` satisfies this).
    static func abbreviateHome(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Label for a bundle-less group whose cwd is known. `dirDisplay` is the already
    /// resolved directory string (shortest-unique suffix or `~`-abbreviated full path).
    static func displayLabel(name: String, dirDisplay: String, commandLine: String?) -> String {
        if let command = commandLine, !command.isEmpty {
            return "\(name) — \(dirDisplay) (\(command))"
        }
        return "\(name) — \(dirDisplay)"
    }

    /// Label for a bundle-less group whose cwd could not be read (bare-name collapse).
    static func collapsedLabel(name: String, processCount: Int) -> String {
        let noun = processCount == 1 ? "process" : "processes"
        return "\(name)  (\(processCount) \(noun), dir unavailable)"
    }
}
