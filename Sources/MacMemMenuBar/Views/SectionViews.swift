import SwiftUI
import MacMemCore

/// TOP APPS rows. Tapping a row opens a per-row menu (quit / reveal) via callbacks.
struct TopAppsSection: View {
    let snapshot: MemorySnapshot
    let onQuit: (AppGroup) -> Void
    let onReveal: (AppGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOP APPS").font(.caption).foregroundStyle(.secondary)
            if snapshot.appsStatus == .error {
                Text("Could not read processes.").font(.callout)
            } else {
                ForEach(snapshot.topApps, id: \.name) { app in
                    HStack {
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(app.totalFootprintBytes))
                            .foregroundStyle(.secondary).monospacedDigit()
                        Menu {
                            Button("Quit \(app.name)…") { onQuit(app) }
                            Button("Reveal in Activity Monitor") { onReveal(app) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton).frame(width: 20)
                    }
                }
                if snapshot.unreadableProcessCount > 0 {
                    Text("\(snapshot.unreadableProcessCount) processes not shown (owned by other users).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// SWAP + measured compressed memory.
struct SwapSection: View {
    let snapshot: MemorySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SWAP").font(.caption).foregroundStyle(.secondary)
            if let swap = snapshot.swap {
                Text("Used \(ByteFormat.string(swap.usedBytes)) / \(ByteFormat.string(swap.totalBytes))")
                    .monospacedDigit()
            } else {
                Text("Swap data unavailable.").font(.callout).foregroundStyle(.secondary)
            }
            if !snapshot.compressedAvailable {
                Text("per-app compressed memory unavailable (could not read from top)")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.compressedUsers.prefix(5)), id: \.appName) { e in
                    HStack {
                        Text(e.appName).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(e.compressedBytes))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

/// BROWSER TABS — per-browser measured total + tab list.
struct TabsSection: View {
    let snapshot: MemorySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BROWSER TABS").font(.caption).foregroundStyle(.secondary)
            if snapshot.tabsStatus == .permissionNeeded {
                PermissionBanner(text: "Allow Automation to read browser tabs.",
                                 actionTitle: "Open Settings", action: openAutomationSettings)
            } else {
                ForEach(snapshot.browsers, id: \.browser) { b in
                    let total = b.totalFootprintBytes.map { ByteFormat.string($0) } ?? "not separately attributable"
                    Text("\(b.browser) — \(total) · \(b.tabs.count) tabs")
                        .font(.callout)
                }
                if snapshot.tabsStatus == .partial {
                    Text("some browsers could not be read.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
