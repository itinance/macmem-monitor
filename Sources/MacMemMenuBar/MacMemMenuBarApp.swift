import SwiftUI
import MacMemCore

@main
struct MacMemMenuBarApp: App {
    @StateObject private var model = MenuViewModel(
        provider: NativeMemoryProvider(),
        tabSource: AppleScriptTabSource(),
        actions: LiveSystemActions())

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
                .onAppear { model.setMenuOpen(true) }
                .onDisappear { model.setMenuOpen(false) }
        } label: {
            BarLabel(pressure: model.pressure)
        }
        .menuBarExtraStyle(.window)
    }
}
