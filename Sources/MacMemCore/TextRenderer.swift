import Foundation

public enum TextRenderer {
    // Column widths for fixed-width table layout.
    // NAME_WIDTH: characters reserved for the app name (long names are truncated with "…").
    private static let nameWidth = 30
    // MEM_WIDTH: characters reserved for the right-aligned memory string (e.g. "  1.5 MB").
    private static let memWidth = 10
    // TAB_MEM_WIDTH: characters reserved for the tab memory field (includes "~" prefix and label).
    private static let tabMemWidth = 20

    /// Left-aligns `s` in a field of exactly `width` characters.
    /// Names longer than `width - 1` are truncated and get a trailing "…".
    private static func nameColumn(_ s: String, width: Int = nameWidth) -> String {
        if s.count <= width {
            return s.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        // Truncate to (width - 1) chars and append the ellipsis character.
        let truncated = String(s.prefix(width - 1)) + "…"
        return truncated
    }

    /// Right-aligns `s` in a field of exactly `width` characters.
    private static func memColumn(_ s: String, width: Int = memWidth) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }

    public static func render(_ snap: MemorySnapshot, includeSwap: Bool = true, includeTabs: Bool = true) -> String {
        var lines: [String] = []

        lines.append("== TOP APPS (by combined memory) ==")
        lines.append(statusNote(snap.appsStatus, unreadable: snap.unreadableProcessCount))
        for (i, app) in snap.topApps.enumerated() {
            let name = nameColumn(app.name)
            let mem  = memColumn(ByteFormat.string(app.totalFootprintBytes))
            lines.append(String(format: "%2d. %@  %@  (%d proc)", i + 1, name, mem, app.processCount))
        }

        if includeSwap {
            lines.append("")
            lines.append("== SWAP ==")
            if let swap = snap.swap {
                lines.append("Used \(ByteFormat.string(swap.usedBytes)) / \(ByteFormat.string(swap.totalBytes))"
                             + "   (in: \(swap.swapIns), out: \(swap.swapOuts))")
            } else {
                // Swap totals unavailable, but measured compressed memory may still be present.
                lines.append(statusNote(snap.swapStatus, unreadable: 0))
            }
            if !snap.compressedUsers.isEmpty {
                lines.append("")
                lines.append("Compressed memory per app (measured — RAM held by the compressor, swap precursor):")
                for c in snap.compressedUsers {
                    lines.append("   \(ByteFormat.string(c.compressedBytes))  \(c.appName)  [measured]")
                }
                if snap.compressedUnreadableCount > 0 {
                    lines.append("   (\(snap.compressedUnreadableCount) processes could not be read from top)")
                }
            } else if snap.swap != nil {
                lines.append("")
                if snap.compressedAvailable {
                    lines.append("Compressed memory per app: none measured.")
                } else {
                    lines.append("Compressed memory per app: unavailable (could not read from top).")
                }
            }
        }

        if includeTabs {
            lines.append("")
            lines.append("== BROWSER TABS (heaviest) ==")
            // Always show the status note for non-ok states, even when some tabs were returned
            // (e.g. partial: browser A succeeded, browser B failed — show what we got plus the note).
            if snap.tabsStatus != .ok {
                lines.append(tabsStatusNote(snap.tabsStatus))
            }
            for (i, tab) in snap.topTabs.enumerated() {
                if let bytes = tab.estimatedBytes {
                    // Carry the confidence label on estimated rows (spec: every estimate has a marker)
                    let mem = memColumn("~\(ByteFormat.string(bytes)) [\(tab.confidence.rawValue)]",
                                        width: tabMemWidth)
                    lines.append(String(format: "%2d. %@  %@", i + 1, mem, tab.url))
                } else {
                    let mem = memColumn("(n/a)", width: tabMemWidth)
                    lines.append(String(format: "%2d. %@  %@", i + 1, mem, tab.url))
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func statusNote(_ status: SectionStatus, unreadable: Int) -> String {
        switch status {
        case .ok: return unreadable > 0 ? "(\(unreadable) processes not readable)" : ""
        case .partial: return "(partial — \(unreadable) processes not readable; run with sudo for full coverage)"
        case .permissionNeeded: return "(permission needed — grant Automation access to read browser tabs)"
        case .error: return "(unavailable — failed to read this section)"
        }
    }

    /// FINDING 7: tabs-section-specific status note — AppleScript/TCC errors have nothing
    /// to do with sudo or unreadable process counts.
    private static func tabsStatusNote(_ status: SectionStatus) -> String {
        switch status {
        case .ok: return ""
        case .partial: return "(partial — some browsers could not be read)"
        case .permissionNeeded: return "(permission needed — grant Automation access to read browser tabs)"
        case .error: return "(unavailable — failed to read browser tabs)"
        }
    }
}
