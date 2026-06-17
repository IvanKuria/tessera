import SwiftUI
import KalshiKit

/// A compact depth ladder: YES asks (red) descending to the spread, a mid row,
/// then YES bids (green) descending. Each row has a faint cumulative-depth bar.
struct OrderBookView: View {
    let orderbook: Orderbook
    var levelsPerSide: Int = 8

    /// One ladder row.
    private struct Row: Identifiable {
        let id = UUID()
        let priceCents: Int
        let size: Decimal
        let cumulative: Decimal
    }

    /// Asks nearest the spread last (best ask at the bottom of the asks block).
    private var askRows: [Row] {
        // yesAskLevels ascending by price; best (lowest) ask nearest the spread.
        let levels = orderbook.yesAskLevels.sorted { $0.priceCents < $1.priceCents }
        let top = Array(levels.prefix(levelsPerSide))
        // Cumulative from the spread outward (best ask first).
        var cum: Decimal = 0
        var rows: [Row] = []
        for level in top {
            cum += level.size
            rows.append(Row(priceCents: level.priceCents, size: level.size, cumulative: cum))
        }
        // Display worst ask on top, best ask just above the spread.
        return rows.reversed()
    }

    /// Bids nearest the spread first (best bid at the top of the bids block).
    private var bidRows: [Row] {
        let levels = orderbook.yesBidLevels.sorted { $0.priceCents > $1.priceCents }
        let top = Array(levels.prefix(levelsPerSide))
        var cum: Decimal = 0
        var rows: [Row] = []
        for level in top {
            cum += level.size
            rows.append(Row(priceCents: level.priceCents, size: level.size, cumulative: cum))
        }
        return rows
    }

    private var maxCumulative: Decimal {
        let a = askRows.map(\.cumulative).max() ?? 0
        let b = bidRows.map(\.cumulative).max() ?? 0
        return Swift.max(a, b, 1)
    }

    private var spreadCents: Int? {
        guard let ask = orderbook.bestYesAsk, let bid = orderbook.bestYesBid else { return nil }
        return ask - bid
    }

    private var midCents: Double? {
        guard let ask = orderbook.bestYesAsk, let bid = orderbook.bestYesBid else { return nil }
        return Double(ask + bid) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Order Book")
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 10)

            if askRows.isEmpty && bidRows.isEmpty {
                Text("No resting orders")
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 2) {
                    ForEach(askRows) { row in ladderRow(row, tint: Theme.no) }
                }
                spreadRow
                    .padding(.vertical, 6)
                VStack(spacing: 2) {
                    ForEach(bidRows) { row in ladderRow(row, tint: Theme.yes) }
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

    private func ladderRow(_ row: Row, tint: Color) -> some View {
        let fraction = CGFloat(NSDecimalNumber(decimal: row.cumulative / maxCumulative).doubleValue)
        return GeometryReader { geo in
            ZStack(alignment: .trailing) {
                tint.opacity(0.08)
                    .frame(width: max(0, geo.size.width * min(1, fraction)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack {
                    Text("\(row.priceCents)¢")
                        .font(Theme.num(12.5, .semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Text(sizeText(row.size))
                        .font(Theme.num(12, .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(height: 22)
    }

    private var spreadRow: some View {
        HStack {
            Text("Spread")
                .font(Theme.ui(10.5, .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let mid = midCents {
                Text("\(Int(mid.rounded()))¢ mid")
                    .font(Theme.num(11, .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let spread = spreadCents {
                Text("· \(spread)¢")
                    .font(Theme.num(11, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .overlay(Rectangle().fill(Theme.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func sizeText(_ size: Decimal) -> String {
        let value = NSDecimalNumber(decimal: size).doubleValue
        return compactVolume(Int(value.rounded()))
    }
}
