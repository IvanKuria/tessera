import SwiftUI

/// Accessory (menu-bar) mode: no Dock icon by default; flips to regular when a
/// window opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WatchlistStore()
    @State private var account = AccountStore()

    var body: some Scene {
        MenuBarExtra(store.menuBarTitle, systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Tessera", id: "main") {
            DashboardView(store: store, account: account)
                .frame(minWidth: 900, minHeight: 640)
                // Kalshi is a light UI; pin it so it reads right under any system theme.
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentMinSize)
    }
}
