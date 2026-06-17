import SwiftUI

/// The compact themed popover shown from the menu-bar item.
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

            Divider().overlay(Theme.stroke)

            if store.events.isEmpty {
                Text(store.errorMessage ?? "Loading markets…")
                    .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.events.prefix(9)) { event in
                            MenuBarRow(event: event)
                            Divider().overlay(Theme.stroke.opacity(0.6))
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider().overlay(Theme.stroke)
            HStack {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Tessera", systemImage: "macwindow")
                        .font(Theme.body(12, .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.mint)
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Text("Quit").font(Theme.body(12)).foregroundStyle(Theme.textTertiary)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(Theme.body(12.5, .medium)).foregroundStyle(Theme.text)
                    .lineLimit(1)
                ProbabilityBar(percent: event.topOutcome?.percent ?? 0, height: 4)
                    .frame(width: 180)
            }
            Spacer(minLength: 6)
            Text(event.topOutcome?.percent.map { "\($0)%" } ?? "—")
                .font(Theme.mono(14, .bold)).foregroundStyle(Theme.mint)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
