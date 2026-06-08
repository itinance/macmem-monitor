import SwiftUI

/// The app shell is intentionally minimal: the menubar status item and its dropdown are
/// owned by `AppDelegate` via AppKit (`NSStatusItem` + `NSPopover`) for reliable toggle
/// behavior and to avoid the `MenuBarExtra(.window)` row-menu hang. The `Settings` scene
/// exists only to give the SwiftUI `App` a valid (and, for an `LSUIElement` accessory app,
/// invisible) scene; there is no main window.
@main
struct MacMemMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
