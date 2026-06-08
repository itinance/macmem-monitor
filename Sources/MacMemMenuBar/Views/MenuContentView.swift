import SwiftUI
import MacMemCore

/// The dropdown body. Reads everything from the view model.
struct MenuContentView: View {
    @ObservedObject var model: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = model.snapshot {
                TopAppsSection(snapshot: snapshot,
                               onQuit: { model.requestQuit($0) },
                               onReveal: { model.reveal($0) })
                Divider()
                SwapSection(snapshot: snapshot)
                Divider()
                TabsSection(snapshot: snapshot)
            } else {
                Text("Measuring…").foregroundStyle(.secondary)
            }

            if let msg = model.lastActionMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button("Purge…") { model.requestPurge() }
                Button("Copy") { model.copySnapshot() }
                Spacer()
                Button("Quit macmem") { NSApplication.shared.terminate(nil) }
            }
            if let updated = model.lastUpdated {
                Text("updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 360)
        .confirmationDialog("Confirm", isPresented: confirmBinding, presenting: model.pendingConfirmation) { pending in
            Button(confirmTitle(pending), role: .destructive) {
                Task { await model.confirmPending() }
            }
            Button("Cancel", role: .cancel) { model.cancelPending() }
        } message: { pending in
            Text(confirmMessage(pending))
        }
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { model.pendingConfirmation != nil },
                set: { if !$0 { model.cancelPending() } })
    }

    private func confirmTitle(_ p: PendingConfirmation) -> String {
        switch p {
        case .quit(let app): return "Quit \(app.name)"
        case .purge:         return "Run purge"
        }
    }

    private func confirmMessage(_ p: PendingConfirmation) -> String {
        switch p {
        case .quit(let app):
            return "Quit \(app.name) (\(ByteFormat.string(app.totalFootprintBytes)))? Unsaved work may be lost."
        case .purge:
            return "Run purge? It flushes disk caches and briefly spikes disk I/O. You'll be asked for your admin password."
        }
    }
}
