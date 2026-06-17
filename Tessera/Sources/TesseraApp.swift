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
            DashboardView(store: store, account: account)
                .frame(minWidth: 900, minHeight: 640)
                // Kalshi is a light UI; pin it so it reads right under any system theme.
                .preferredColorScheme(.light)
                // Start the ambient + flagship engines once the UI is up.
                .task {
                    await alerts.start()
                    await triggers.start()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .windowList) {
                OpenAutomationCommand()
            }
        }

        Window("Alerts & Triggers", id: "automation") {
            AutomationView(alerts: alerts, triggers: triggers)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Menu command (⌥⌘A) to open the automation control panel.
private struct OpenAutomationCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Alerts & Triggers") { openWindow(id: "automation") }
            .keyboardShortcut("a", modifiers: [.option, .command])
    }
}
