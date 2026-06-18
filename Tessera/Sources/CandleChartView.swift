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
    /// Live last-traded price (cents) from the WebSocket feed, when connected. The
    /// latest (forming) candle and the last-price line tick to this; closed
    /// historical candles stay fixed.
    var liveLastCents: Int? = nil

    @State private var showVolume = true
    @State private var showSpread = true
    @State private var showMA = true
    @State private var logScale = false
    @State private var selectedID: Int?

    // Pinch-to-zoom (trackpad)
    @State private var zoomRange: ClosedRange<Int>?
    @State private var pinchBase: (center: Double, half: Double)?

    private var fullBounds: (lo: Double, hi: Double) {
        (Double((candles.first?.id ?? 0) - 1), Double((candles.last?.id ?? 1) + 1))
    }
    private var currentBounds: (lo: Double, hi: Double) {
        if let z = zoomRange { return (Double(z.lowerBound), Double(z.upperBound)) }
        return fullBounds
    }

    /// Pinch on the trackpad to zoom the x-window around its center.
    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let cur = currentBounds
                if pinchBase == nil {
                    // Zoom around the hovered candle (cursor) if any, else the center.
                    let anchor = selectedID.map(Double.init) ?? (cur.lo + cur.hi) / 2
                    pinchBase = (min(max(anchor, cur.lo), cur.hi), (cur.hi - cur.lo) / 2)
                }
                guard let base = pinchBase else { return }
                let full = fullBounds
                let maxHalf = (full.hi - full.lo) / 2
                var half = min(max(base.half / max(0.2, value.magnification), 2), maxHalf)
                var lo = base.center - half, hi = base.center + half
                if lo < full.lo { hi += full.lo - lo; lo = full.lo }
                if hi > full.hi { lo -= hi - full.hi; hi = full.hi }
                lo = max(lo, full.lo); hi = min(hi, full.hi)
                let loi = Int(lo.rounded()), hii = Int(hi.rounded())
                guard hii - loi >= 2 else { return }
                zoomRange = (loi <= Int(full.lo.rounded()) && hii >= Int(full.hi.rounded())) ? nil : loi...hii
                _ = half
            }
            .onEnded { _ in pinchBase = nil }
    }

    /// The latest bar re-priced to the live tick (O(1)); nil when there's no live
    /// price. We never rebuild the whole candle array — that allocates on every
    /// hover move and tick. Instead, only the last bar is substituted in place.
    private var formedLast: CandleVM? {
        guard let live = liveLastCents, let last = candles.last else { return nil }
        let c = Double(live)
        return CandleVM(
            id: last.id, date: last.date, open: last.open,
            high: max(last.high, c), low: min(last.low, c), close: c,
            volume: last.volume, yesBid: last.yesBid, yesAsk: last.yesAsk
        )
    }

    /// The live-adjusted version of the latest candle, else the candle unchanged.
    private func display(_ c: CandleVM) -> CandleVM {
        (c.id == candles.last?.id ? formedLast : nil) ?? c
    }

    /// Candles inside the current zoom window (or all). Backed by the stored array
    /// (no copy when unzoomed) — the live tip is overlaid at render time instead.
    private var visibleCandles: [CandleVM] {
        guard let z = zoomRange else { return candles }
        let inside = candles.filter { z.contains($0.id) }
        return inside.count >= 2 ? inside : candles
    }

    /// Simple moving average period, scaled to the candle count.
    private var maPeriod: Int { max(3, min(12, candles.count / 4)) }

    /// SMA of closes, one point per candle once the window fills.
    private var movingAverage: [(id: Int, value: Double)] {
        guard candles.count >= maPeriod else { return [] }
        var closes = candles.map(\.close)
        if let f = formedLast { closes[closes.count - 1] = f.close }
        var out: [(Int, Double)] = []
        for i in (maPeriod - 1)..<candles.count {
            let avg = closes[(i - maPeriod + 1)...i].reduce(0, +) / Double(maPeriod)
            out.append((candles[i].id, avg))
        }
        return out
    }

    // MARK: - Derived (precomputed, never per-mark)

    /// Fast O(1) lookup for the hovered candle (latest bar shows the live tip).
    private var byID: [Int: CandleVM] {
        var d = Dictionary(uniqueKeysWithValues: candles.map { ($0.id, $0) })
        if let f = formedLast { d[f.id] = f }
        return d
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
        let lows = visibleCandles.map(\.low)
        let highs = visibleCandles.map(\.high)
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
        let current = (formedLast ?? candles.last)?.close ?? 0
        let base = candles.first?.open ?? current
        let change = current - base
        let up = change >= 0
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(Int(current.rounded()))¢")
                .font(Theme.num(26, .semibold)).foregroundStyle(Theme.text)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text(changeString(change))   // points (¢); relative % is meaningless near 0¢
            }
            .font(Theme.num(13, .semibold)).foregroundStyle(up ? Theme.yes : Theme.no)
            Text("· \(timeframe.rawValue)").font(Theme.ui(12)).foregroundStyle(Theme.textTertiary)
            if liveLastCents != nil {
                HStack(spacing: 4) {
                    Circle().fill(Theme.yes).frame(width: 6, height: 6)
                    Text("LIVE").font(Theme.ui(9, .bold)).tracking(0.5).foregroundStyle(Theme.yes)
                }
            }
            Spacer(minLength: 8)
            let hi = visibleCandles.map(\.high).max() ?? current
            let lo = visibleCandles.map(\.low).min() ?? current
            Text("H \(Int(hi.rounded()))¢  L \(Int(lo.rounded()))¢")
                .font(Theme.num(11)).foregroundStyle(Theme.textTertiary)
            if showMA {
                Text("MA\(maPeriod)").font(Theme.num(11, .semibold)).foregroundStyle(Theme.info)
            }
        }
    }

    @ViewBuilder private var chartArea: some View {
        if hasData {
            VStack(spacing: 6) {
                priceChart.frame(height: 320).clipped()
                if showVolume {
                    volumeChart.frame(height: 80).clipped()
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
            if zoomRange != nil {
                chip("Reset", isOn: false) { withAnimation { zoomRange = nil } }
            }
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

            ForEach(candles) { c0 in
                let c = display(c0)
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
                        .foregroundStyle(Theme.info)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
            }

            // Always-on last-price line + tag at the latest close (live when connected).
            if let last = formedLast ?? candles.last {
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
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
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
        .gesture(magnify)
    }

    // MARK: - Volume chart

    private var volumeChart: some View {
        Chart {
            ForEach(candles) { c in
                BarMark(
                    x: .value("Bar", c.id),
                    y: .value("Volume", min(c.volume, volumeYMax)),
                    width: .ratio(0.6)
                )
                .foregroundStyle((c.isUp ? Theme.yes : Theme.no).opacity(0.55))
            }
        }
        .chartXScale(domain: xDomainValues)
        .chartYScale(domain: 0...volumeYMax)
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

    /// Shared x-scale domain for both panels — the zoom window if set, else full.
    private var xDomainValues: ClosedRange<Int> {
        zoomRange ?? xDomain ?? 0...1
    }

    /// Top of the volume axis: the 95th-percentile bar (with headroom), not the
    /// max. Prediction-market volume is heavily right-skewed — a single settlement
    /// or launch bar can be 100× a normal day — so scaling to the true max flattens
    /// every ordinary bar to a sub-pixel sliver. Outliers clip to the top instead.
    private var volumeYMax: Double {
        let vols = visibleCandles.map(\.volume).filter { $0 > 0 }.sorted()
        guard let maxV = vols.last else { return 1 }
        let p95 = vols[Int(Double(vols.count - 1) * 0.95)]
        // If volume is fairly uniform, just use the real max; else clamp to p95.
        let top = (maxV <= p95 * 2) ? maxV : p95
        return max(top * 1.15, 1)
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
