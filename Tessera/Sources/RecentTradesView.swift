import SwiftUI
import KalshiKit

/// The public trade tape: newest first, YES price colored by taker side.
struct RecentTradesView: View {
    let trades: [Trade]
    var maxRows: Int = 20

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var rows: [Trade] {
        Array(
            trades.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
                .prefix(maxRows)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Trades")
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 10)

            if rows.isEmpty {
                Text("No recent trades")
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, trade in
                    tradeRow(trade)
                    if index < rows.count - 1 {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
        )
    }

    private func tradeRow(_ trade: Trade) -> some View {
        let tint = trade.takerSide == .yes ? Theme.yes : Theme.no
        return HStack {
            Text(relativeTime(trade.createdDate))
                .font(Theme.num(11.5, .regular))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(priceCents(trade).map { "\($0)¢" } ?? "—")
                .font(Theme.num(12.5, .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, alignment: .trailing)
            Text(sizeText(trade))
                .font(Theme.num(12, .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func priceCents(_ trade: Trade) -> Int? {
        if let dollars = trade.yesPriceDollars?.value {
            return Int(NSDecimalNumber(decimal: dollars * 100).doubleValue.rounded())
        }
        return trade.yesPrice
    }

    private func sizeText(_ trade: Trade) -> String {
        if let count = trade.countFp?.doubleValue {
            return compactVolume(Int(count.rounded()))
        }
        if let count = trade.count {
            return compactVolume(count)
        }
        return "—"
    }
}
