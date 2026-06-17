import SwiftUI

/// Standard app behavior: quit when the main window is closed (single-window app).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
