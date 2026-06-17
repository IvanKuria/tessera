import SwiftUI
import KalshiKit

/// The Portfolio screen — a faithful Kalshi-light account view. White background,
/// hairline cards, no shadows; tabular figures for every number; cents for
/// prices. Presents balance + portfolio value, open positions, resting orders
/// (cancelable), recent fills, and settled markets.
struct PortfolioView: View {
    var store: PortfolioStore
    var onClose: () -> Void = {}
    /// Hidden when embedded as a sidebar section (no sheet to dismiss).
    var showsClose: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(spacing: 16) {
                    if store.isLoading && store.positions.isEmpty {
                        loadingState
                    }
                    if let error = store.errorMessage {
                        errorBanner(error)
                    }
                    positionsCard
                    openOrdersCard
                    fillsCard
                    settledCard
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.bg)
        .frame(minWidth: 560, minHeight: 620)
        .task { await store.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Portfolio")
                    .font(Theme.condensed(28, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    Task { await store.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.subtle))
                }
                .buttonStyle(.plain)
                .help("Refresh")

                if showsClose {
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.subtle))
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 28) {
                balanceHeadline(
                    label: "Available",
                    cents: store.balanceCents
                )
                balanceHeadline(
                    label: "Portfolio value",
                    cents: store.portfolioValueCents,
                    big: false
                )
                Spacer()
                pnlHeadline
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private func balanceHeadline(label: String, cents: Int?, big: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Theme.ui(10, .semibold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text(Format.dollars(cents: cents))
                .font(Theme.num(big ? 30 : 19, big ? .semibold : .medium))
                .foregroundStyle(Theme.text)
        }
    }

    private var pnlHeadline: some View {
        let pnl = store.totalRealizedPnl
        let positive = pnl >= 0
        return VStack(alignment: .trailing, spacing: 3) {
            Text("REALIZED P&L")
                .font(Theme.ui(10, .semibold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text(Format.signedDollars(pnl))
                .font(Theme.num(19, .semibold))
                .foregroundStyle(positive ? Theme.yes : Theme.no)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading your portfolio…")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.no)
            Text(message)
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.no.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.no.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Positions

    private var positionsCard: some View {
        Card(title: "Positions", count: store.positions.count) {
            if store.positions.isEmpty {
                EmptyRow(text: "No open positions.")
            } else {
                ForEach(Array(store.positions.enumerated()), id: \.element.id) { index, p in
                    if index > 0 { rowDivider }
                    PositionRow(position: p)
                }
            }
        }
    }

    // MARK: - Open orders

    private var openOrdersCard: some View {
        Card(title: "Open Orders", count: store.openOrders.count) {
            if store.openOrders.isEmpty {
                EmptyRow(text: "No resting orders.")
            } else {
                ForEach(Array(store.openOrders.enumerated()), id: \.element.id) { index, o in
                    if index > 0 { rowDivider }
                    OrderRow(order: o) {
                        Task { await store.cancel(orderId: o.orderId) }
                    }
                }
            }
        }
    }

    // MARK: - Fills

    private var fillsCard: some View {
        Card(title: "Recent Fills", count: store.fills.count) {
            if store.fills.isEmpty {
                EmptyRow(text: "No recent fills.")
            } else {
                ForEach(Array(store.fills.enumerated()), id: \.element.id) { index, f in
                    if index > 0 { rowDivider }
                    FillRow(fill: f)
                }
            }
        }
    }

    // MARK: - Settled

    private var settledCard: some View {
        Card(title: "Settled", count: store.settlements.count) {
            if store.settlements.isEmpty {
                EmptyRow(text: "Nothing settled yet.")
            } else {
                ForEach(Array(store.settlements.enumerated()), id: \.element.id) { index, s in
                    if index > 0 { rowDivider }
                    SettlementRow(settlement: s)
                }
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.border)
    }
}

// MARK: - Card shell

/// A hairline-bordered, flat white card with an eyebrow header (and count badge).
private struct Card<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Eyebrow(text: title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Theme.num(10.5, .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.subtle))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

private struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.ui(13))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
    }
}

// MARK: - Rows

private struct PositionRow: View {
    let position: MarketPosition

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(position.ticker)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Format.contracts(position.position))
                    .font(Theme.num(11.5, .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            StatBlock(label: "Exposure", value: Format.dollars(decimal: position.marketExposureDollars?.value))
            pnlBlock
        }
        .padding(.vertical, 12)
    }

    private var pnlBlock: some View {
        let pnl = position.realizedPnlDollars?.value ?? 0
        let positive = pnl >= 0
        return VStack(alignment: .trailing, spacing: 2) {
            Text(Format.signedDollars(pnl))
                .font(Theme.num(14, .semibold))
                .foregroundStyle(pnl == 0 ? Theme.textSecondary : (positive ? Theme.yes : Theme.no))
            Text("P&L").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(minWidth: 72, alignment: .trailing)
    }
}

private struct OrderRow: View {
    let order: Order
    var onCancel: () -> Void

    private var tint: Color { order.side == .no ? Theme.no : Theme.yes }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(order.ticker ?? "—")
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Format.actionSide(action: order.action, side: order.side))
                        .font(Theme.ui(11.5, .semibold))
                        .foregroundStyle(tint)
                    Text(Format.cents(order.side == .no ? order.noPrice : order.yesPrice))
                        .font(Theme.num(11.5, .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(order.remainingCount ?? order.count ?? 0)")
                    .font(Theme.num(13, .semibold))
                    .foregroundStyle(Theme.text)
                Text(order.remainingCount != nil ? "REMAINING" : "CONTRACTS")
                    .font(Theme.ui(9, .semibold)).tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
            }
            CancelButton(action: onCancel)
        }
        .padding(.vertical, 12)
    }
}

private struct CancelButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Cancel")
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(Theme.no)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(Theme.no.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FillRow: View {
    let fill: Fill

    private var tint: Color { fill.side == .no ? Theme.no : Theme.yes }
    private var priceCents: Int? {
        let dollars = fill.side == .no ? fill.noPriceDollars : fill.yesPriceDollars
        guard let dollars else { return nil }
        return NSDecimalNumber(decimal: dollars.value * 100).intValue
    }
    private var size: Int {
        if let c = fill.count { return c }
        if let fp = fill.countFp { return NSDecimalNumber(decimal: fp.value).intValue }
        return 0
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fill.ticker)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Format.actionSide(action: fill.action, side: fill.side))
                        .font(Theme.ui(11.5, .semibold))
                        .foregroundStyle(tint)
                    Text(Format.relative(fill.createdDate))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            Text(Format.cents(priceCents))
                .font(Theme.num(13, .medium))
                .foregroundStyle(Theme.text)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(size)")
                    .font(Theme.num(13, .semibold))
                    .foregroundStyle(Theme.text)
                Text("SIZE").font(Theme.ui(9, .semibold)).tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.vertical, 12)
    }
}

private struct SettlementRow: View {
    let settlement: Settlement

    private var result: String { (settlement.marketResult ?? "—").uppercased() }
    private var resultTint: Color {
        switch (settlement.marketResult ?? "").lowercased() {
        case "yes": return Theme.yes
        case "no":  return Theme.no
        default:    return Theme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(settlement.ticker)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Format.relative(settlement.settledDate))
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text(result)
                .font(Theme.ui(11, .bold)).tracking(0.5)
                .foregroundStyle(resultTint)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(resultTint.opacity(0.10)))
            revenueBlock
        }
        .padding(.vertical, 12)
    }

    private var revenueBlock: some View {
        let revenue = settlement.revenueDollars?.value ?? 0
        let positive = revenue >= 0
        return VStack(alignment: .trailing, spacing: 2) {
            Text(Format.signedDollars(revenue))
                .font(Theme.num(14, .semibold))
                .foregroundStyle(revenue == 0 ? Theme.textSecondary : (positive ? Theme.yes : Theme.no))
            Text("REVENUE").font(Theme.ui(9, .semibold)).tracking(0.5)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(minWidth: 72, alignment: .trailing)
    }
}

// MARK: - Formatting

/// Small, pure formatting helpers. Money is rendered from `Decimal`/cents with
/// tabular figures; prices render as cents ("62¢").
private enum Format {
    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// "$1,234.56" from integer cents.
    static func dollars(cents: Int?) -> String {
        guard let cents else { return "—" }
        return dollars(decimal: Decimal(cents) / 100)
    }

    /// "$1,234.56" from a dollar `Decimal`.
    static func dollars(decimal: Decimal?) -> String {
        guard let decimal else { return "—" }
        return currency.string(from: NSDecimalNumber(decimal: decimal)) ?? "$0.00"
    }

    /// Signed dollars, e.g. "+$12.40" / "−$3.00".
    static func signedDollars(_ value: Decimal) -> String {
        let magnitude = abs(value)
        let body = currency.string(from: NSDecimalNumber(decimal: magnitude)) ?? "$0.00"
        if value < 0 { return "−" + body }
        return "+" + body
    }

    /// Price in cents, e.g. "62¢".
    static func cents(_ cents: Int?) -> String {
        guard let cents else { return "—" }
        return "\(cents)¢"
    }

    /// Signed contract count with side, e.g. "+12 YES" / "−5 NO".
    static func contracts(_ position: Int?) -> String {
        guard let position, position != 0 else { return "—" }
        let side = position > 0 ? "YES" : "NO"
        let sign = position > 0 ? "+" : "−"
        return "\(sign)\(abs(position)) \(side)"
    }

    /// "Buy YES" / "Sell NO" style label.
    static func actionSide(action: OrderAction?, side: OrderSide?) -> String {
        let a: String
        switch action {
        case .buy:  a = "Buy"
        case .sell: a = "Sell"
        default:    a = ""
        }
        let s: String
        switch side {
        case .yes: s = "YES"
        case .no:  s = "NO"
        default:   s = ""
        }
        return [a, s].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Relative time, e.g. "3h ago".
    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    nonisolated(unsafe) private static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
}
