import SwiftUI
import AppKit

/// A small inline banner with an optional action button. Used for the
/// Automation-denied case and the "N processes unreadable" note.
struct PermissionBanner: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.callout)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Opens System Settings → Privacy & Security → Automation.
func openAutomationSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
        NSWorkspace.shared.open(url)
    }
}
