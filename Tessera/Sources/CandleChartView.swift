import SwiftUI
import Charts

/// Pro-style candlestick + volume chart for a single focused market. Candles are
/// plotted against a **categorical bar index** (`CandleVM.id`) so weekend/overnight
/// gaps don't open holes in the timeline. A faint bid/ask spread band sits behind
/// the candles, an optional volume panel hangs below, and a hover crosshair scrubs
/// an OHLC tooltip styled to match `PriceChartView`.
struct CandleChartView: View {
    let candles: [CandleVM]
    let isLoading: Bool
    @Binding var timeframe: DetailStore.Timeframe
    var onTimeframeChange: () -> Void = {}

    @State private var showVolume = true
    @State private var showSpread = true
    @State private var showMA = true
    @State private var logScale = false
    @State private var selectedID: Int?

    /// Simple moving average period, scaled to the candle count.
    private var maPeriod: Int { max(3, min(12, candles.count / 4)) }

    /// SMA of closes, one point per candle once the window fills.
    private var movingAverage: [(id: Int, value: Double)] {
        guard candles.count >= maPeriod else { return [] }
        let closes = candles.map(\.close)
        var out: [(Int, Double)] = []
        for i in (maPeriod - 1)..<candles.count {
            let avg = closes[(i - maPeriod + 1)...i].reduce(0, +) / Double(maPeriod)
            out.append((candles[i].id, avg))
        }
        return out
    }

    // MARK: - Derived (precomputed, never per-mark)

    /// Fast O(1) lookup for the hovered candle.
    private var byID: [Int: CandleVM] {
        Dictionary(uniqueKeysWithValues: candles.map { ($0.id, $0) })
    }

    private var selectedCandle: CandleVM? {
        guard let selectedID else { return nil }
        return byID[selectedID]
    }

    private var hasData: Bool { candles.count >= 2 }

    /// Shared x-domain (bar index range with half-bar padding) so the price and
    /// volume panels line up column-for-column.
    private var xDomain: ClosedRange<Int>? {
        guard let first = candles.first?.id, let last = candles.last?.id else { return nil }
        return (first - 1)...(last + 1)
    }

    /// Dynamic y-domain from low…high, padded ~6%, clamped to [0,100]. In log mode
    /// the lower bound is kept strictly above 0 (> 0.5¢).
    private var yDomain: ClosedRange<Double> {
        let lows = candles.map(\.low)
        let highs = candles.map(\.high)
        guard let lo = lows.min(), let hi = highs.max(), hi > lo else {
            return logScale ? 0.5...100 : 0...100
        }
        let pad = (hi - lo) * 0.06
        var lower = lo - pad
        var upper = hi + pad
        if logScale {
            lower = max(lower, 0.5)
            upper = min(upper, 100)
        } else {
            lower = max(lower, 0)
            upper = min(upper, 100)
        }
        if lower >= upper { lower = logScale ? 0.5 : 0; upper = 100 }
        return lower...upper
    }

    /// Sparse y tick values across the active domain.
    private var yTicks: [Double] {
        let d = yDomain
        let steps = 4
        let span = d.upperBound - d.lowerBound
        return (0...steps).map { d.lowerBound + span * Double($0) / Double(steps) }
    }

    /// 4–6 bar indices mapped back to their dates for the x-axis labels.
    private var xAxisDates: [Int: Date] {
        guard !candles.isEmpty else { return [:] }
        let desired = min(5, candles.count)
        guard desired > 1 else {
            if let c = candles.first { return [c.id: c.date] }
            return [:]
        }
        var out: [Int: Date] = [:]
        let stride = Double(candles.count - 1) / Double(desired - 1)
        for i in 0..<desired {
            let idx = Int((Double(i) * stride).rounded())
            let c = candles[min(idx, candles.count - 1)]
            out[c.id] = c.date
        }
        return out
    }

    private var axisIndices: [Int] { xAxisDates.keys.sorted() }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlRow
            if hasData { priceReadout }
            chartArea
        }
    }

    /// Current price + change over the visible window.
    private var priceReadout: some View {
        let current = candles.last?.close ?? 0
        let base = candles.first?.open ?? current
        let change = current - base
        let pct = base > 0 ? change / base * 100 : 0
        let up = change >= 0
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(Int(current.rounded()))¢")
                .font(Theme.num(26, .semibold)).foregroundStyle(Theme.text)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text("\(changeString(change)) (\(up ? "+" : "−")\(String(format: "%.1f", abs(pct)))%)")
            }
            .font(Theme.num(13, .semibold)).foregroundStyle(up ? Theme.yes : Theme.no)
            Text("· \(timeframe.rawValue)").font(Theme.ui(12)).foregroundStyle(Theme.textTertiary)
            Spacer()
        }
    }

    @ViewBuilder private var chartArea: some View {
        if hasData {
            VStack(spacing: 6) {
                priceChart.frame(height: 320)
                if showVolume {
                    volumeChart.frame(height: 80)
                }
            }
        } else if isLoading {
            placeholder { ProgressView().controlSize(.small) }
        } else {
            placeholder {
                Text("No candles").font(Theme.ui(13, .medium)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack { content() }.frame(maxWidth: .infinity).frame(height: 320)
    }

    // MARK: - Control row

    private var controlRow: some View {
        HStack(spacing: 8) {
            chip("MA", isOn: showMA) { showMA.toggle() }
            chip("Vol", isOn: showVolume) { showVolume.toggle() }
            chip("Spread", isOn: showSpread) { showSpread.toggle() }
            chip("Log", isOn: logScale) { logScale.toggle() }
            Spacer(minLength: 12)
            selector
        }
    }

    private func chip(_ label: String, isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.ui(11.5, .medium))
                .foregroundStyle(isOn ? Theme.text : Theme.textTertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isOn ? Theme.subtle : Color.clear)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var selector: some View {
        HStack(spacing: 18) {
            ForEach(DetailStore.Timeframe.allCases, id: \.self) { tf in
                Button {
                    guard tf != timeframe else { return }
                    timeframe = tf
                    onTimeframeChange()
                } label: {
                    Text(tf.rawValue)
                        .font(Theme.ui(13, .medium))
                        .foregroundStyle(tf == timeframe ? Theme.text : Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Price chart

    private var priceChart: some View {
        Chart {
            // Spread band first, so it sits behind the candles.
            if showSpread {
                ForEach(candles) { c in
                    if let bid = c.yesBid, let ask = c.yesAsk {
                        AreaMark(
                            x: .value("Bar", c.id),
                            yStart: .value("Bid", bid),
                            yEnd: .value("Ask", ask)
                        )
                        .foregroundStyle(Theme.textSecondary.opacity(0.10))
                        .interpolationMethod(.stepCenter)
                    }
                }
            }

            ForEach(candles) { c in
                let color = c.isUp ? Theme.yes : Theme.no

                // Wick.
                RuleMark(
                    x: .value("Bar", c.id),
                    yStart: .value("Low", c.low),
                    yEnd: .value("High", c.high)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.4))

                // Body. Doji (open ≈ close) gets a thin sliver so it stays visible.
                let bodyLow = min(c.open, c.close)
                let bodyHigh = max(c.open, c.close)
                let doji = (bodyHigh - bodyLow) < 0.15
                let lo = doji ? bodyLow - 0.075 : bodyLow
                let hi = doji ? bodyHigh + 0.075 : bodyHigh
                RectangleMark(
                    x: .value("Bar", c.id),
                    yStart: .value("Open", lo),
                    yEnd: .value("Close", hi),
                    width: .ratio(0.6)
                )
                .foregroundStyle(color)
            }

            // Moving-average trend line over the candle closes (amber).
            if showMA {
                ForEach(movingAverage, id: \.id) { p in
                    LineMark(x: .value("Bar", p.id), y: .value("MA", p.value),
                             series: .value("series", "ma"))
                        .foregroundStyle(Color(hex: 0xF59F00))
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
            }

            // Always-on last-price line + tag at the latest close.
            if let last = candles.last {
                let up = (candles.first.map { last.close >= $0.open } ?? true)
                RuleMark(y: .value("Last", last.close))
                    .foregroundStyle((up ? Theme.yes : Theme.no).opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .trailing, alignment: .center, spacing: 0) {
                        priceTag("\(Int(last.close.rounded()))¢", fill: up ? Theme.yes : Theme.no)
                    }
            }

            // Hover crosshair: vertical rule + OHLC tooltip, plus a price tag on the axis.
            if let sel = selectedID, let c = byID[sel] {
                RuleMark(x: .value("Bar", sel))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(c)
                    }
                RuleMark(y: .value("Hover", c.close))
                    .foregroundStyle(Theme.textTertiary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .trailing, alignment: .center, spacing: 0) {
                        priceTag("\(Int(c.close.rounded()))¢", fill: Theme.text)
                    }
            }
        }
        .chartYScale(domain: yDomain, type: logScale ? .log : .linear)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yTicks) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v.rounded()))¢")
                            .font(Theme.num(10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXScale(domain: xDomainValues)
        .chartXAxis {
            AxisMarks(values: axisIndices) { value in
                AxisValueLabel {
                    if let idx = value.as(Int.self), let date = xAxisDates[idx] {
                        Text(date, format: dateAxisFormat)
                            .font(Theme.num(9.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedID)
    }

    // MARK: - Volume chart

    private var volumeChart: some View {
        Chart {
            ForEach(candles) { c in
                BarMark(
                    x: .value("Bar", c.id),
                    y: .value("Volume", c.volume),
                    width: .ratio(0.6)
                )
                .foregroundStyle((c.isUp ? Theme.yes : Theme.no).opacity(0.45))
            }
        }
        .chartXScale(domain: xDomainValues)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(compactVolumeLabel(v))
                            .font(Theme.num(9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    /// Shared x-scale domain for both panels (falls back to a unit range if empty).
    private var xDomainValues: ClosedRange<Int> {
        xDomain ?? 0...1
    }

    // MARK: - Tooltip

    private func tooltip(_ c: CandleVM) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.date, format: dateTooltipFormat)
                .font(Theme.num(9.5)).foregroundStyle(Theme.textTertiary)

            HStack(spacing: 10) {
                ohlc("O", c.open)
                ohlc("H", c.high)
            }
            HStack(spacing: 10) {
                ohlc("L", c.low)
                ohlc("C", c.close)
            }

            HStack(spacing: 6) {
                Text(changeString(c.change))
                    .font(Theme.num(11, .semibold))
                    .foregroundStyle(c.change >= 0 ? Theme.yes : Theme.no)
                Spacer(minLength: 6)
                Text("Vol \(compactVolumeLabel(c.volume))")
                    .font(Theme.num(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minWidth: 124)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    /// A small colored axis price tag (last-price / crosshair).
    private func priceTag(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(Theme.num(9.5, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }

    private func ohlc(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.ui(9.5, .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            Text("\(Int(value.rounded()))¢")
                .font(Theme.num(11, .semibold))
                .foregroundStyle(Theme.text)
        }
        .frame(width: 52)
    }

    // MARK: - Formatting

    /// `+N¢` / `−N¢` (true minus sign), rounded to whole cents.
    private func changeString(_ v: Double) -> String {
        let n = Int(v.rounded())
        if n >= 0 { return "+\(n)¢" }
        return "−\(abs(n))¢"
    }

    /// Compact volume label, e.g. 1_240 → "1.2k".
    private func compactVolumeLabel(_ v: Double) -> String {
        let n = max(0, v)
        switch n {
        case 1_000_000...: return String(format: "%.1fM", n / 1_000_000)
        case 1_000...:     return String(format: "%.1fk", n / 1_000)
        default:           return "\(Int(n.rounded()))"
        }
    }

    /// Intraday timeframes label as `HH:mm`; daily and longer as `MMM d`.
    private var dateAxisFormat: Date.FormatStyle {
        switch timeframe {
        case .h1:
            return .dateTime.hour(.twoDigits(amPM: .omitted)).minute()
        default:
            return .dateTime.month(.abbreviated).day()
        }
    }

    /// Tooltip date: intraday shows the time too; daily+ shows the date only.
    private var dateTooltipFormat: Date.FormatStyle {
        switch timeframe {
        case .h1:
            return .dateTime.month(.abbreviated).day().hour().minute()
        default:
            return .dateTime.month(.abbreviated).day().year()
        }
    }
}
