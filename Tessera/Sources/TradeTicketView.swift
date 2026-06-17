import SwiftUI
import KalshiKit

/// The Kalshi right-docked trade ticket, presented here as a ~340pt panel/sheet.
/// If the account isn't connected it embeds `OnboardingView` instead. Otherwise
/// it offers BUY/SELL, a YES/NO segmented pill, Market/Limit order types, a
/// quantity stepper, a live preview, and an explicit confirm step before any
/// order is placed. Prices are in CENTS throughout.
struct TradeTicketView: View {
    var account: AccountStore
    let marketTicker: String
    let eventTitle: String
    var initialSide: OrderSide = .yes

    // Order builder state.
    @State private var didSetInitialSide = false
    @State private var action: OrderAction = .buy
    @State private var side: OrderSide = .yes
    @State private var isLimit: Bool = false
    @State private var limitCents: Int = 50
    @State private var count: Int = 1

    // Live quote (display only) fetched keyless on appear.
    @State private var yesAskCents: Int?
    @State private var noAskCents: Int?
    @State private var impliedPercent: Int?

    // Confirmation + result.
    @State private var isConfirming = false
    @State private var placedOrderId: String?

    private let panelWidth: CGFloat = 340

    var body: some View {
        Group {
            if account.isSignedIn {
                ticket
            } else {
                OnboardingView(account: account)
                    .frame(minWidth: panelWidth)
            }
        }
    }

    // MARK: - Ticket

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            buySellTabs
            yesNoPill
            orderTypeToggle
            if isLimit { limitField }
            quantityField
            preview
            footer
        }
        .padding(20)
        .frame(width: panelWidth, alignment: .leading)
        .background(Theme.bg)
        .onAppear {
            if !didSetInitialSide {
                side = initialSide
                didSetInitialSide = true
            }
        }
        .task(id: marketTicker) { await loadQuote() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(eventTitle)
                    .font(Theme.condensed(18, .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(account.env.badge)
                    .font(Theme.ui(9.5, .bold))
                    .tracking(0.8)
                    .foregroundStyle(account.env == .production ? Theme.no : Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(account.env == .production ? Theme.no.opacity(0.08) : Theme.subtle)
                    )
            }
            Text(marketTicker)
                .font(Theme.num(10.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var buySellTabs: some View {
        HStack(spacing: 20) {
            tabButton("Buy", isActive: action == .buy) { action = .buy }
            tabButton("Sell", isActive: action == .sell) { action = .sell }
            Spacer()
        }
    }

    private func tabButton(_ title: String, isActive: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 5) {
                Text(title)
                    .font(Theme.ui(14, isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Theme.text : Theme.textTertiary)
                Capsule()
                    .fill(isActive ? Theme.text : .clear)
                    .frame(width: 22, height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    /// The headline YES/NO segmented pill: a capsule track with a sliding
    /// tinted highlight (green YES / red NO), selected label white, showing the
    /// side's ask price in cents.
    private var yesNoPill: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            ZStack(alignment: side == .yes ? .leading : .trailing) {
                Capsule().fill(Theme.subtle)
                Capsule()
                    .fill(side == .yes ? Theme.yes : Theme.no)
                    .frame(width: half)
                    .animation(.snappy(duration: 0.18), value: side)
                HStack(spacing: 0) {
                    pillLabel("Yes", cents: yesAskCents, selected: side == .yes)
                    pillLabel("No", cents: noAskCents, selected: side == .no)
                }
            }
        }
        .frame(height: 46)
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    private func pillLabel(_ title: String, cents: Int?, selected: Bool) -> some View {
        Button {
            side = title == "Yes" ? .yes : .no
        } label: {
            HStack(spacing: 5) {
                Text(title).font(Theme.ui(14, .semibold))
                Text(cents.map { "\($0)¢" } ?? "—").font(Theme.num(14, .semibold))
            }
            .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var orderTypeToggle: some View {
        HStack(spacing: 0) {
            segment("Market", isActive: !isLimit) { isLimit = false }
            segment("Limit", isActive: isLimit) {
                isLimit = true
                if let p = sidePriceCents { limitCents = p }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.subtle))
    }

    private func segment(_ title: String, isActive: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(Theme.ui(12.5, .medium))
                .foregroundStyle(isActive ? Theme.text : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive ? Theme.surface : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var limitField: some View {
        HStack {
            Text("Limit price")
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            stepper(
                value: limitCents,
                suffix: "¢",
                decrement: { limitCents = max(1, limitCents - 1) },
                increment: { limitCents = min(99, limitCents + 1) }
            )
        }
    }

    private var quantityField: some View {
        HStack {
            Text("Contracts")
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            stepper(
                value: count,
                suffix: "",
                decrement: { count = max(1, count - 1) },
                increment: { count = min(10_000, count + 1) }
            )
        }
    }

    private func stepper(value: Int, suffix: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            stepperButton(system: "minus", action: decrement)
            Text("\(value)\(suffix)")
                .font(Theme.num(14, .semibold))
                .foregroundStyle(Theme.text)
                .frame(minWidth: 54)
            stepperButton(system: "plus", action: increment)
        }
        .padding(3)
        .background(Capsule().fill(Theme.subtle))
    }

    private func stepperButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(spacing: 10) {
            previewRow("Odds", value: impliedPercent.map { "\($0)% chance" } ?? "—")
            previewRow("Est. cost", value: currency(estCostCents))
            previewRow("Max payout", value: currency(count * 100))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.subtle))
    }

    private func previewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.num(13, .semibold))
                .foregroundStyle(Theme.text)
        }
    }

    // MARK: - Footer (review / confirm / result)

    @ViewBuilder
    private var footer: some View {
        if let orderId = placedOrderId {
            successBanner(orderId)
        } else if isConfirming {
            confirmation
        } else {
            reviewButton
            if let error = account.lastError {
                inlineError(error)
            }
        }
    }

    private var reviewButton: some View {
        Button {
            account.lastError = nil
            isConfirming = true
        } label: {
            Text("Review order")
                .font(Theme.ui(15, .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(sideTint))
                .opacity(count >= 1 ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(count < 1)
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Text(confirmSummary)
                .font(Theme.ui(13, .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if account.env == .production {
                Text("This is a REAL order on production.")
                    .font(Theme.ui(11, .semibold))
                    .foregroundStyle(Theme.no)
            }

            HStack(spacing: 10) {
                Button {
                    isConfirming = false
                } label: {
                    Text("Cancel")
                        .font(Theme.ui(14, .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(Theme.subtle))
                }
                .buttonStyle(.plain)
                .disabled(account.isWorking)

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 7) {
                        if account.isWorking {
                            ProgressView().controlSize(.small).tint(Theme.onAccent)
                        }
                        Text(account.isWorking ? "Placing…" : "Confirm")
                            .font(Theme.ui(14, .semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Capsule().fill(sideTint))
                }
                .buttonStyle(.plain)
                .disabled(account.isWorking)
            }

            if let error = account.lastError {
                inlineError(error)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func successBanner(_ orderId: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.yes)
                Text("Order placed ✓")
                    .font(Theme.ui(14, .semibold))
                    .foregroundStyle(Theme.text)
            }
            Text(orderId)
                .font(Theme.num(10))
                .foregroundStyle(Theme.textTertiary)
            Button {
                placedOrderId = nil
                isConfirming = false
            } label: {
                Text("Place another")
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.yes)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.yes.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.yes.opacity(0.25), lineWidth: 1))
    }

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(Theme.ui(11.5))
            .foregroundStyle(Theme.no)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Submit

    private func submit() async {
        let result = await account.placeOrder(
            marketTicker: marketTicker,
            action: action,
            side: side,
            count: count,
            limitCents: isLimit ? limitCents : nil
        )
        switch result {
        case .success(let order):
            placedOrderId = order.orderId
            isConfirming = false
        case .failure:
            // lastError is already set by the store; stay on the confirm step.
            break
        }
    }

    // MARK: - Quote loading (keyless, display-only)

    private func loadQuote() async {
        let client = KalshiClient(environment: account.env.kalshi)
        do {
            let market = try await client.market(marketTicker)
            yesAskCents = Self.cents(market.yesAskDollars)
            noAskCents = Self.cents(market.noAskDollars)
            impliedPercent = market.impliedPercent
            // Seed the limit price with the live ask for the current side.
            if let p = sidePriceCents { limitCents = p }
        } catch {
            // Display prices are best-effort; leave them as "—" on failure.
        }
    }

    // MARK: - Derived values

    private var sideTint: Color { side == .yes ? Theme.yes : Theme.no }

    /// The live ask price (cents) for the currently selected side.
    private var sidePriceCents: Int? {
        side == .yes ? yesAskCents : noAskCents
    }

    /// Per-contract price used for cost preview: limit uses the entered price;
    /// market uses the live ask for the side.
    private var unitPriceCents: Int? {
        isLimit ? limitCents : sidePriceCents
    }

    private var estCostCents: Int {
        (unitPriceCents ?? 0) * count
    }

    private var confirmSummary: String {
        let verb = action == .buy ? "Buy" : "Sell"
        let sideLabel = side == .yes ? "YES" : "NO"
        let pricePart: String
        if isLimit {
            pricePart = "@ \(limitCents)¢ (limit)"
        } else if let p = sidePriceCents {
            pricePart = "@ ~\(p)¢ (market)"
        } else {
            pricePart = "(market)"
        }
        return "\(verb) \(count) \(sideLabel) \(pricePart) — est. cost \(currency(estCostCents)). Place order?"
    }

    // MARK: - Formatting

    private func currency(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    private static func cents(_ value: KalshiDecimal?) -> Int? {
        guard let value else { return nil }
        return Int(NSDecimalNumber(decimal: value.value * 100).doubleValue.rounded())
    }
}
