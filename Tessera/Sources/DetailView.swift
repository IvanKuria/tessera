import SwiftUI
import KalshiKit

/// The event / market detail screen: header stats, price chart, buy controls,
/// order book, trade tape, and (binary) rules — laid out Kalshi-style on a flat
/// white canvas. Handles both binary and multi-outcome events.
struct DetailView: View {
    let event: EventVM
    var account: AccountStore
    var alerts: AlertEngine
    var onBuy: (_ marketTicker: String, _ side: OrderSide) -> Void = { _, _ in }

    @State private var store = DetailStore()
    @State private var selectedOutcomeID: String?
    @State private var chartMode: ChartMode = .line

    // Inline alert composer (shared by the line + candle charts).
    @State private var showAlertBar = false
    @State private var alertCents: Double = 50
    @State private var alertAbove = true
    @State private var alertAdded = false

    /// The trade ticket is presented BY this view (not bubbled to the dashboard).
    /// Presenting from the pushed detail's own context fixes the sheet failing to
    /// appear until you navigate back (nested NavigationStack-in-SplitView quirk).
    @State private var ticketTarget: TradeTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if event.isBinary {
                    binaryBody
                } else {
                    multiBody
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("")
        .task {
            await store.load(event: event)
            await store.startLive(signer: account.liveSigner, environment: account.kalshiEnvironment)
        }
        .onDisappear { store.stopLive() }
        .onChange(of: store.timeframe) { _, _ in
            Task { await store.loadChartSeries(); await store.loadFocusedCandles() }
        }
        .sheet(item: $ticketTarget) { target in
            TradeTicketView(account: account,
                            marketTicker: target.marketTicker,
                            eventTitle: target.eventTitle,
                            initialSide: target.side)
                .frame(width: 380, height: 580)
        }
    }

    /// Open the trade ticket for a market from this detail view.
    private func buy(_ marketTicker: String, _ side: OrderSide) {
        ticketTarget = TradeTarget(marketTicker: marketTicker, eventTitle: event.title, side: side)
    }

    /// Toggle which outcome is emphasized on the chart (and focus its book/trades).
    /// Tapping the selected one again clears the highlight so every line shows.
    private func select(_ id: String) {
        if selectedOutcomeID == id {
            selectedOutcomeID = nil
        } else {
            selectedOutcomeID = id
            Task { await store.focus(marketTicker: id) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                EventIcon(event: event, size: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: event.category)
                    Text(event.title)
                        .font(Theme.condensed(26, .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            statsStrip
                .padding(.top, 2)
        }
    }

    private var statsStrip: some View {
        HStack(alignment: .top, spacing: 28) {
            StatBlock(label: "Last", value: lastPriceText, valueColor: Theme.text)
            StatBlock(label: "24h Volume", value: volume24hText)
            StatBlock(label: "Open Interest", value: openInterestText)
            StatBlock(label: "Closes", value: closeCountdownText)
        }
    }

    // MARK: - Binary layout

    private var binaryBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            bigPriceHeadline
            chart
            buyRow(marketTicker: store.focusedMarketTicker,
                   yesCents: focusedYesCents, noCents: focusedNoCents)
            HStack(alignment: .top, spacing: 16) {
                if store.orderbook != nil {
                    OrderBookView(orderbook: store.orderbook ?? Orderbook())
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                RecentTradesView(trades: store.trades)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            rulesSection
        }
    }

    private var bigPriceHeadline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(impliedPercentText)
                .font(Theme.num(48, .semibold))
                .foregroundStyle(Theme.text)
            if let delta = priceDelta {
                HStack(spacing: 3) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(abs(delta))¢")
                        .font(Theme.num(15, .semibold))
                }
                .foregroundStyle(delta >= 0 ? Theme.yes : Theme.no)
            }
            if store.isLive {
                LiveDot().padding(.leading, 4)
            }
        }
    }

    // MARK: - Multi-outcome layout

    private var multiBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            chart
            VStack(spacing: 0) {
                ForEach(Array(event.outcomes.enumerated()), id: \.element.id) { index, outcome in
                    outcomeRow(outcome)
                    if index < event.outcomes.count - 1 {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
            )
            HStack(alignment: .top, spacing: 16) {
                if store.orderbook != nil {
                    OrderBookView(orderbook: store.orderbook ?? Orderbook())
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                RecentTradesView(trades: store.trades)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func outcomeRow(_ outcome: OutcomeVM) -> some View {
        let isSelected = outcome.id == selectedOutcomeID
        let dot = store.color(forOutcome: outcome.id)
        return HStack(spacing: 12) {
            // Tapping the label area focuses this outcome (updates book/trades).
            Button {
                select(outcome.id)
            } label: {
                HStack(spacing: 13) {
                    OutcomeAvatar(name: outcome.label, ring: dot ?? Theme.textTertiary, size: 44,
                                  peopleLikely: CategoryStyle.hasPeopleOutcomes(event.category))
                    Text(outcome.label)
                        .font(Theme.ui(15.5, isSelected ? .semibold : .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(outcome.percent.map { "\($0)%" } ?? "—")
                        .font(Theme.num(18, .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 60, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            QuickBuyButton(side: .yes, cents: outcome.yesCents) { buy(outcome.id, .yes) }
                .frame(width: 96)
            QuickBuyButton(side: .no, cents: outcome.noCents) { buy(outcome.id, .no) }
                .frame(width: 96)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(isSelected ? Theme.subtle : Color.clear)
    }

    // MARK: - Shared pieces

    /// Label of the market the candles are charting (multi-outcome → the focused
    /// outcome, which defaults to the leader).
    private var candleOutcomeLabel: String? {
        guard !event.isBinary else { return nil }
        return event.outcomes.first { $0.id == store.focusedMarketTicker }?.label
            ?? event.topOutcome?.label
    }

    private var chart: some View {
        // Timeframe changes are observed by `.onChange(of: store.timeframe)`, which
        // refetches both the line series and candles.
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                chartModeToggle
                if chartMode == .candles, let label = candleOutcomeLabel {
                    Text("· \(label)")
                        .font(Theme.ui(12, .medium)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                alertToggle
            }

            if showAlertBar { alertBar }

            if chartMode == .candles {
                CandleChartView(
                    candles: store.focusedCandles,
                    isLoading: store.isLoading,
                    timeframe: Binding(get: { store.timeframe }, set: { store.timeframe = $0 }),
                    onTimeframeChange: { Task { await store.loadFocusedCandles() } },
                    liveLastCents: store.liveLastCents
                )
            } else {
                PriceChartView(
                    series: store.chartSeries,
                    isLoading: store.isLoading,
                    timeframe: Binding(get: { store.timeframe }, set: { store.timeframe = $0 }),
                    highlightedID: selectedOutcomeID,
                    onSelectSeries: { select($0) }
                )
            }
        }
    }

    private var chartModeToggle: some View {
        HStack(spacing: 0) {
            chartModeButton("Line", .line)
            chartModeButton("Candles", .candles)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
    }

    private func chartModeButton(_ title: String, _ mode: ChartMode) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { chartMode = mode } } label: {
            Text(title)
                .font(Theme.ui(12, chartMode == mode ? .semibold : .regular))
                .foregroundStyle(chartMode == mode ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(chartMode == mode ? Theme.surface : Color.clear))
        }
        .buttonStyle(.plain)
    }

    /// Standalone Alert toggle, sat beside the Line/Candles control. Works in both
    /// chart modes — alerts are about the focused market, not the chart style.
    private var alertToggle: some View {
        Button {
            if !showAlertBar {
                alertCents = Double(focusedYesCents ?? Int(store.liveLastCents ?? 50))
                alertAdded = false
            }
            withAnimation(.easeOut(duration: 0.15)) { showAlertBar.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showAlertBar ? "bell.fill" : "bell")
                    .font(.system(size: 11, weight: .semibold))
                Text("Alert").font(Theme.ui(12, .semibold))
            }
            .foregroundStyle(showAlertBar ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(showAlertBar ? Theme.yes : Theme.subtle))
        }
        .buttonStyle(.plain)
    }

    /// Inline composer to create a price alert at a chosen level + direction.
    private var alertBar: some View {
        HStack(spacing: 10) {
            Text("Notify when").font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 0) {
                alertDirSeg("Rises to ≥", true)
                alertDirSeg("Falls to ≤", false)
            }
            HStack(spacing: 6) {
                alertStep("minus") { alertCents = max(1, alertCents - 1); alertAdded = false }
                Text("\(Int(alertCents))¢").font(Theme.num(13, .semibold)).foregroundStyle(Theme.text).frame(width: 38)
                alertStep("plus") { alertCents = min(99, alertCents + 1); alertAdded = false }
            }
            Button {
                alerts.addRule(AlertRule(
                    marketTicker: store.focusedMarketTicker,
                    label: candleOutcomeLabel ?? event.title,
                    thresholdCents: Int(alertCents),
                    crossesUpward: alertAbove
                ))
                withAnimation { alertAdded = true }
            } label: {
                Text("Add alert").font(Theme.ui(12, .semibold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.yes))
            }
            .buttonStyle(.plain)
            if alertAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(Theme.ui(11, .semibold)).foregroundStyle(Theme.yes)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtle))
    }

    private func alertDirSeg(_ title: String, _ above: Bool) -> some View {
        Button { alertAbove = above } label: {
            Text(title)
                .font(Theme.ui(11.5, alertAbove == above ? .semibold : .regular))
                .foregroundStyle(alertAbove == above ? Theme.text : Theme.textTertiary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(alertAbove == above ? Theme.surface : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func alertStep(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.surface).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private func buyRow(marketTicker: String, yesCents: Int?, noCents: Int?) -> some View {
        HStack(spacing: 12) {
            QuickBuyButton(side: .yes, cents: yesCents) { buy(marketTicker, .yes) }
                .scaleEffect(1.0)
            QuickBuyButton(side: .no, cents: noCents) { buy(marketTicker, .no) }
        }
        .font(Theme.ui(16, .semibold))
    }

    @State private var rulesExpanded = false

    @ViewBuilder
    private var rulesSection: some View {
        if let rulesText = rulesText {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { rulesExpanded.toggle() }
                } label: {
                    HStack {
                        Text("Rules")
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: rulesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)

                if rulesExpanded {
                    Text(rulesText)
                        .font(Theme.ui(13, .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
            )
        }
    }

    // MARK: - Derived display values

    private var focusedYesCents: Int? {
        if let live = store.liveYesAskCents { return live }
        if let dollars = store.market?.yesAskDollars?.value {
            return cents(dollars)
        }
        return store.market?.yesAsk ?? focusedOutcome?.yesCents
    }

    private var focusedNoCents: Int? {
        if let live = store.liveNoAskCents { return live }
        if let dollars = store.market?.noAskDollars?.value {
            return cents(dollars)
        }
        return store.market?.noAsk ?? focusedOutcome?.noCents
    }

    private var focusedOutcome: OutcomeVM? {
        event.outcomes.first { $0.id == store.focusedMarketTicker } ?? event.topOutcome
    }

    private var impliedPercentText: String {
        if let live = store.liveLastCents { return "\(live)%" }
        if let pct = store.market?.impliedPercent { return "\(pct)%" }
        if let pct = focusedOutcome?.percent { return "\(pct)%" }
        return "—"
    }

    private var lastPriceText: String {
        if let live = store.liveLastCents { return "\(live)¢" }
        if let dollars = store.market?.lastPriceDollars?.value {
            return "\(cents(dollars) ?? 0)¢"
        }
        if let last = store.market?.lastPrice { return "\(last)¢" }
        if let yes = focusedOutcome?.yesCents { return "\(yes)¢" }
        return "—"
    }

    /// Last minus previous, in cents (for the up/down headline delta).
    private var priceDelta: Int? {
        guard let last = store.market?.lastPriceDollars?.value,
              let prev = store.market?.previousPriceDollars?.value else { return nil }
        let lastC = cents(last) ?? 0
        let prevC = cents(prev) ?? 0
        return lastC - prevC
    }

    private var volume24hText: String {
        if let v = store.market?.volume24hFp?.doubleValue {
            return compactVolume(Int(v.rounded()))
        }
        if let v = store.market?.volumeFp?.doubleValue {
            return compactVolume(Int(v.rounded()))
        }
        return compactVolume(event.totalVolume)
    }

    private var openInterestText: String {
        if let oi = store.market?.openInterestFp?.doubleValue {
            return compactVolume(Int(oi.rounded()))
        }
        if let oi = store.market?.openInterest { return compactVolume(oi) }
        return "—"
    }

    private var closeCountdownText: String {
        guard let close = event.closeTime else { return "—" }
        let interval = close.timeIntervalSinceNow
        if interval <= 0 { return "Closed" }
        let days = Int(interval) / 86_400
        let hours = (Int(interval) % 86_400) / 3_600
        if days > 0 { return "\(days)d \(hours)h" }
        let minutes = (Int(interval) % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Best-effort rules text from the market (Kalshi's Market model has no
    /// dedicated rules fields in this SDK; we surface subtitle/yes/no subtitles).
    private var rulesText: String? {
        guard let market = store.market else { return nil }
        let parts = [market.subtitle, market.yesSubTitle, market.noSubTitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let combined = parts.joined(separator: "\n\n")
        return combined.isEmpty ? nil : combined
    }

    private func cents(_ dollars: Decimal) -> Int? {
        Int(NSDecimalNumber(decimal: dollars * 100).doubleValue.rounded())
    }
}
