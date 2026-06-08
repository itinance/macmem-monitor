import AppKit
import Combine
import SwiftUI
import MacMemCore

/// Owns the menubar status item and the dropdown popover directly via AppKit, instead
/// of SwiftUI's `MenuBarExtra(.window)`. Two concrete behaviors require this:
///
///  1. **Toggle.** A second click on the status icon reliably CLOSES the popover.
///     `MenuBarExtra(.window)` does not dependably dismiss on a repeat icon click.
///  2. **Row menus don't hang.** The per-app `Menu` (Quit) runs inside a real popover
///     window. Under `MenuBarExtra(.window)` that nested `NSMenu` tracking loop conflicts
///     with the window-style extra and beachballs the app.
///
/// The popover uses `.applicationDefined` behavior (we dismiss it ourselves) so a click
/// on the status icon while it's open is delivered to our toggle action rather than being
/// swallowed by transient auto-dismiss and immediately re-opening.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MenuViewModel(
        provider: NativeMemoryProvider(),
        tabSource: AppleScriptTabSource(),
        actions: LiveSystemActions())

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        applyPressure(model.pressure)

        popover.behavior = .applicationDefined
        popover.animates = false
        let host = NSHostingController(rootView: MenuContentView(model: model))
        host.sizingOptions = [.preferredContentSize]   // popover tracks the SwiftUI height
        popover.contentViewController = host

        // Keep the bar symbol/tint in sync with measured pressure.
        model.$pressure
            .sink { [weak self] in self?.applyPressure($0) }
            .store(in: &cancellables)

        // Close the popover when the app loses focus (e.g. Cmd-Tab away).
        NotificationCenter.default.addObserver(
            self, selector: #selector(closePopover),
            name: NSApplication.didResignActiveNotification, object: nil)

        model.start()
    }

    /// Update the status-bar image + tint. Template image so it adapts to the menubar
    /// appearance; `contentTintColor` overrides it for known pressure levels and is left
    /// nil for `.unknown` so the bar never shows a fabricated "all good" green.
    private func applyPressure(_ pressure: MemoryPressure) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: PressureStyle.symbolName(for: pressure),
                            accessibilityDescription: PressureStyle.tooltip(for: pressure))
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = AppDelegate.tint(for: pressure)
        button.toolTip = PressureStyle.tooltip(for: pressure)
    }

    private static func tint(for pressure: MemoryPressure) -> NSColor? {
        switch pressure {
        case .normal:   return .systemGreen
        case .warn:     return .systemYellow
        case .critical: return .systemRed
        case .unknown:  return nil   // adaptive menubar color — never a fake green
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.setMenuOpen(true)
        // Dismiss on any click outside the popover (clicks on our own status button go to
        // the toggle action instead, since global monitors only see other-app events).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    @objc private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        model.setMenuOpen(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
