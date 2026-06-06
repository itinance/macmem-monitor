import Foundation

public enum TextRenderer {
    public static func render(_ snap: MemorySnapshot) -> String {
        var lines: [String] = []

        lines.append("== TOP APPS (by combined memory) ==")
        lines.append(statusNote(snap.appsStatus, unreadable: snap.unreadableProcessCount))
        for (i, app) in snap.topApps.enumerated() {
            lines.append(String(format: "%2d. %-28@  %10@  (%d proc)",
                                i + 1, app.name as NSString,
                                ByteFormat.string(app.totalFootprintBytes) as NSString,
                                app.processCount))
        }

        lines.append("")
        lines.append("== SWAP ==")
        if let swap = snap.swap {
            lines.append("Used \(ByteFormat.string(swap.usedBytes)) / \(ByteFormat.string(swap.totalBytes))"
                         + "   (in: \(swap.swapIns), out: \(swap.swapOuts))")
            if snap.swapCulprits.isEmpty {
                lines.append("No swap in use, or no estimable culprits.")
            } else {
                lines.append("Likely contributors (estimates):")
                for c in snap.swapCulprits {
                    lines.append("   ~ \(c.appName)  [\(c.confidence.rawValue)]")
                }
            }
        } else {
            lines.append(statusNote(snap.swapStatus, unreadable: 0))
        }

        lines.append("")
        lines.append("== BROWSER TABS (heaviest) ==")
        if snap.topTabs.isEmpty {
            lines.append(statusNote(snap.tabsStatus, unreadable: 0))
        } else {
            for (i, tab) in snap.topTabs.enumerated() {
                let mem = tab.estimatedBytes.map { "~\(ByteFormat.string($0))" } ?? "  (n/a)"
                lines.append(String(format: "%2d. %10@  %@", i + 1, mem as NSString, tab.url as NSString))
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
}
