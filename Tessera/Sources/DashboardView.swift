import SwiftUI
import KalshiKit

/// The full-window market browser.
struct DashboardView: View {
    var store: WatchlistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Markets").font(.title2.bold())
                    Text("Unofficial app for Kalshi — not affiliated")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let updated = store.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }
            .padding()

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            Table(store.markets) {
                TableColumn("Market") { market in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(market.title ?? market.ticker).lineLimit(1)
                        Text(market.ticker).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TableColumn("Yes") { market in
                    Text(market.yesAskDollars.map { dollars($0) } ?? "—").monospacedDigit()
                }
                .width(70)
                TableColumn("Implied") { market in
                    Text(market.impliedPercent.map { "\($0)%" } ?? "—")
                        .monospacedDigit().bold()
                }
                .width(80)
            }
        }
    }

    private func dollars(_ value: KalshiDecimal) -> String {
        // value is in dollars (e.g. 0.56) → show as cents ("56¢").
        let cents = NSDecimalNumber(decimal: value.value * 100).intValue
        return "\(cents)¢"
    }
}
