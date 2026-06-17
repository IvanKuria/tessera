import Foundation
import SwiftUI
import KalshiKit

/// Drives the event/market detail screen: a multi-line probability chart (one
/// line per top outcome, like Kalshi), plus the focused market's order book and
/// trade tape. Per-section failures are tolerated so one dead endpoint never
/// blanks the screen.
@MainActor
@Observable
final class DetailStore {
    /// Chart timeframe windows; each maps to a (start, candle-period) pair.
    enum Timeframe: String, CaseIterable, Sendable {
        case h1 = "1H"
        case d1 = "1D"
        case w1 = "1W"
        case m1 = "1M"
        case all = "ALL"

        /// `(startTs, periodInterval)` relative to `now`. Tuned for small candle
        /// counts (≤ ~365) — `period_interval` only supports 1, 60, or 1440.
        func window(now: Int) -> (startTs: Int, periodInterval: Int) {
            switch self {
            case .h1:  return (now - 3_600, 1)          // ~60 one-minute candles
            case .d1:  return (now - 86_400, 60)        // ~24 hourly candles
            case .w1:  return (now - 604_800, 60)       // ~168 hourly candles
            case .m1:  return (now - 2_592_000, 1_440)  // ~30 daily candles
            case .all: return (now - 31_536_000, 1_440) // ~365 daily candles
            }
        }
    }

    /// One charted sample with a stable identity (index), so SwiftUI reuses marks.
    struct ChartPoint: Identifiable, Sendable, Hashable {
        let id: Int
        let date: Date
        let percent: Double
    }

    /// One outcome's line on the chart.
    struct SeriesLine: Identifiable, Sendable, Hashable {
        let id: String           // market ticker
        let label: String
        let colorHex: UInt32
        let points: [ChartPoint]
        var color: Color { Color(hex: colorHex) }
        var lastPercent: Double? { points.last?.percent }
    }

    /// Distinct line colors (top outcome = Kalshi green, then blue/orange/purple/teal).
    static let linePalette: [UInt32] = [0x0AC285, 0x265CFF, 0xFF6A00, 0xAA00FF, 0x00B5D9]

    private(set) var event: EventVM?
    private(set) var focusedMarketTicker: String = ""
    private(set) var seriesTicker: String = ""

    private(set) var market: Market?
    private(set) var chartSeries: [SeriesLine] = []
    private(set) var orderbook: Orderbook?
    private(set) var trades: [Trade] = []

    var timeframe: Timeframe = .all
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client = KalshiClient(environment: .production)

    /// Initial load: focused-market detail + the chart series, concurrently.
    func load(event: EventVM) async {
        self.event = event
        seriesTicker = event.seriesTicker
        focusedMarketTicker = event.topOutcome?.id ?? ""
        isLoading = true
        errorMessage = nil
        async let detail: Void = loadFocusedDetail(marketTicker: focusedMarketTicker)
        async let chart: Void = loadChartSeries()
        _ = await (detail, chart)
        isLoading = false
    }

    /// Reloads just the focused market's quote/book/trades (multi-outcome selection).
    func focus(marketTicker: String) async {
        guard marketTicker != focusedMarketTicker, !marketTicker.isEmpty else { return }
        focusedMarketTicker = marketTicker
        await loadFocusedDetail(marketTicker: marketTicker)
    }

    private func loadFocusedDetail(marketTicker: String) async {
        guard !marketTicker.isEmpty else { return }
        let client = self.client
        async let marketResult = Self.result { try await client.market(marketTicker) }
        async let orderbookResult = Self.result { try await client.orderbook(ticker: marketTicker, depth: 12) }
        async let tradesResult = Self.result { try await client.trades(ticker: marketTicker, limit: 30, cursor: nil).trades }
        let m = await marketResult
        let ob = await orderbookResult
        let tr = await tradesResult
        market = m.value ?? market
        orderbook = ob.value
        trades = tr.value ?? []
        if m.value == nil, market == nil { errorMessage = m.error }
    }

    /// Fetches candlesticks for the top outcomes concurrently and builds one
    /// colored line each (binary events → a single green line).
    func loadChartSeries() async {
        guard let event else { return }
        let now = Int(Date().timeIntervalSince1970)
        let (startTs, periodInterval) = timeframe.window(now: now)
        let client = self.client
        let series = seriesTicker
        let palette = Self.linePalette
        let chosen = Array(event.outcomes.prefix(event.isBinary ? 1 : 5))

        let fetched: [Int: [Candlestick]] = await withTaskGroup(of: (Int, [Candlestick]).self) { group in
            for (index, outcome) in chosen.enumerated() {
                let ticker = outcome.id
                group.addTask {
                    let candles = (try? await client.candlesticks(
                        seriesTicker: series, ticker: ticker,
                        startTs: startTs, endTs: now, periodInterval: periodInterval
                    )) ?? []
                    return (index, candles)
                }
            }
            var byIndex: [Int: [Candlestick]] = [:]
            for await (index, candles) in group { byIndex[index] = candles }
            return byIndex
        }

        var lines = chosen.enumerated().compactMap { index, outcome -> SeriesLine? in
            let points = Self.downsample(fetched[index] ?? [])
            guard points.count >= 2 else { return nil }
            return SeriesLine(id: outcome.id, label: outcome.label,
                              colorHex: palette[index % palette.count], points: points)
        }

        // Binary market: pair the green YES line with a mirrored red NO line
        // (NO% = 100 − YES%), the way Kalshi shows both sides.
        if event.isBinary, let yes = lines.first {
            let noPoints = yes.points.map {
                ChartPoint(id: $0.id, date: $0.date, percent: 100 - $0.percent)
            }
            lines = [
                SeriesLine(id: yes.id, label: "Yes", colorHex: 0x0AC285, points: yes.points),
                SeriesLine(id: yes.id + "·NO", label: "No", colorHex: 0xD91616, points: noPoints),
            ]
        }
        chartSeries = lines
    }

    /// Color assigned to a given outcome's line, for tying list rows to the chart.
    func color(forOutcome marketTicker: String) -> Color? {
        chartSeries.first(where: { $0.id == marketTicker })?.color
    }

    /// Reduces candles to chart points, capped via uniform striding.
    nonisolated static func downsample(_ candles: [Candlestick], cap: Int = 180) -> [ChartPoint] {
        let raw: [(Date, Double)] = candles.compactMap { candle in
            guard let date = candle.endPeriodDate, let prob = candle.probability else { return nil }
            return (date, NSDecimalNumber(decimal: prob * 100).doubleValue)
        }
        .sorted { $0.0 < $1.0 }

        guard raw.count > cap else {
            return raw.enumerated().map { ChartPoint(id: $0.offset, date: $0.element.0, percent: $0.element.1) }
        }
        let stride = max(1, raw.count / cap)
        var out: [ChartPoint] = []
        var i = 0
        while i < raw.count {
            out.append(ChartPoint(id: out.count, date: raw[i].0, percent: raw[i].1))
            i += stride
        }
        if let last = raw.last, out.last?.date != last.0 {
            out.append(ChartPoint(id: out.count, date: last.0, percent: last.1))
        }
        return out
    }

    // MARK: - Per-section failure tolerance

    private struct Outcome<T: Sendable>: Sendable {
        var value: T?
        var error: String?
    }

    private nonisolated static func result<T: Sendable>(_ op: @Sendable () async throws -> T) async -> Outcome<T> {
        do {
            return Outcome(value: try await op(), error: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return Outcome(value: nil, error: message)
        }
    }
}
