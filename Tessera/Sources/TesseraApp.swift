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
    @State private var account: AccountStore
    @State private var alerts = AlertEngine()
    @State private var triggers: TriggerEngine

    init() {
        // TriggerEngine needs the account to place orders; build both from one instance.
        let account = AccountStore()
        _account = State(initialValue: account)
        _triggers = State(initialValue: TriggerEngine(account: account))
    }

    var body: some Scene {
        MenuBarExtra(store.menuBarTitle, systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Tessera", id: "main") {
            RootView(store: store, account: account, alerts: alerts, triggers: triggers)
                .frame(minWidth: 980, minHeight: 660)
                // Kalshi is a light UI; pin it so it reads right under any system theme.
                .preferredColorScheme(.light)
                // Start the ambient + flagship engines once the UI is up.
                .task {
                    await alerts.start()
                    await triggers.start()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
