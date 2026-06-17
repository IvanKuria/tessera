import SwiftUI

/// Compact themed popover for the menu-bar item (Kalshi light style).
struct MenuBarView: View {
    var store: WatchlistStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) } else { LiveDot() }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Divider().overlay(Theme.divider)

            if store.events.isEmpty {
                Text(store.errorMessage ?? "Loading markets…")
                    .font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.events.prefix(9)) { event in
                            MenuBarRow(event: event)
                            Divider().overlay(Theme.divider.opacity(0.6))
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider().overlay(Theme.divider)
            HStack {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Tessera", systemImage: "macwindow")
                        .font(Theme.ui(12, .medium)).foregroundStyle(Theme.yes)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Text("Quit").font(Theme.ui(12)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .frame(width: 340)
        .background(Theme.bg)
    }
}

private struct MenuBarRow: View {
    let event: EventVM
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(Theme.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                ProbabilityBar(percent: event.topOutcome?.percent ?? 0, height: 4).frame(width: 190)
            }
            Spacer(minLength: 6)
            Text(event.topOutcome?.percent.map { "\($0)%" } ?? "—")
                .font(Theme.num(14, .semibold)).foregroundStyle(Theme.yes)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
