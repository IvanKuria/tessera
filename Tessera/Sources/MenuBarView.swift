import SwiftUI
import KalshiKit

/// The popover shown when the menu-bar item is clicked.
struct MenuBarView: View {
    var store: WatchlistStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tessera").font(.headline)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            Text("Unofficial • live Kalshi odds")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            if let error = store.errorMessage, store.markets.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if store.markets.isEmpty {
                Text("Loading markets…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.markets.prefix(12), id: \.ticker) { market in
                            MarketRow(market: market)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            HStack {
                Button("Open Window") {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(12)
        .frame(width: 320)
    }
}

/// One compact market row: title + implied probability.
struct MarketRow: View {
    let market: Market

    var body: some View {
        HStack(spacing: 8) {
            Text(market.title ?? market.ticker)
                .lineLimit(1)
                .font(.callout)
            Spacer(minLength: 8)
            Text(market.impliedPercent.map { "\($0)%" } ?? "—")
                .monospacedDigit()
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }
}
