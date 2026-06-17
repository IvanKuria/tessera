import SwiftUI

/// Sets the app to accessory (menu-bar) mode so it has no Dock icon by default.
/// Kept togglable: opening the main window flips to `.regular` and brings it forward.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WatchlistStore()

    var body: some Scene {
        // The live glance. Reading `store.menuBarTitle` here makes the title
        // re-render whenever the @Observable store updates (the documented
        // pattern — a bare @State label does not update reliably).
        MenuBarExtra(store.menuBarTitle, systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Tessera", id: "main") {
            DashboardView(store: store)
                .frame(minWidth: 560, minHeight: 380)
        }
        .windowResizability(.contentMinSize)
    }
}
