import Foundation
import KalshiKit

/// Drives the event/market detail screen: fetches the focused market plus its
/// chart, order book and trade tape, tolerating per-section failures so a single
/// dead endpoint never blanks the whole screen.
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

        /// `(startTs, periodInterval)` relative to `now` (Unix seconds / minutes).
        /// Each window is tuned to yield a small candle count (≤ ~365) so the
        /// chart stays light — `period_interval` only supports 1, 60, or 1440.
        func window(now: Int) -> (startTs: Int, periodInterval: Int) {
            switch self {
            case .h1:  return (now - 3_600, 1)        // ~60 one-minute candles
            case .d1:  return (now - 86_400, 60)      // ~24 hourly candles
            case .w1:  return (now - 604_800, 60)     // ~168 hourly candles
            case .m1:  return (now - 2_592_000, 1_440) // ~30 daily candles
            case .all: return (now - 31_536_000, 1_440) // ~365 daily candles
            }
        }
    }

    private(set) var focusedMarketTicker: String = ""
    private(set) var seriesTicker: String = ""

    private(set) var market: Market?
    private(set) var candles: [Candlestick] = []
    /// Chart-ready, downsampled, stably-identified points (prepared once per load
    /// so the chart view never recomputes over thousands of raw candles).
    private(set) var chartPoints: [ChartPoint] = []
    private(set) var orderbook: Orderbook?
    private(set) var trades: [Trade] = []

    /// One charted sample with a stable identity (index), so SwiftUI reuses marks
    /// across renders instead of rebuilding the whole chart.
    struct ChartPoint: Identifiable, Sendable, Hashable {
        let id: Int
        let date: Date
        let percent: Double
    }

    var timeframe: Timeframe = .d1
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client = KalshiClient(environment: .production)

    /// Full load for a newly focused market: market + orderbook + trades + candles
    /// fetched concurrently, each tolerated independently.
    func load(seriesTicker: String, marketTicker: String) async {
        guard !marketTicker.isEmpty else { return }
        focusedMarketTicker = marketTicker
        self.seriesTicker = seriesTicker
        isLoading = true
        errorMessage = nil

        let (startTs, periodInterval) = timeframe.window(now: Int(Date().timeIntervalSince1970))
        let endTs = Int(Date().timeIntervalSince1970)
        let client = self.client   // capture the Sendable actor, not `self`

        async let marketResult = Self.result { try await client.market(marketTicker) }
        async let orderbookResult = Self.result { try await client.orderbook(ticker: marketTicker, depth: 12) }
        async let tradesResult = Self.result {
            try await client.trades(ticker: marketTicker, limit: 30, cursor: nil).trades
        }
        async let candlesResult = Self.result {
            try await client.candlesticks(
                seriesTicker: seriesTicker, ticker: marketTicker,
                startTs: startTs, endTs: endTs, periodInterval: periodInterval
            )
        }

        let m = await marketResult
        let ob = await orderbookResult
        let tr = await tradesResult
        let cs = await candlesResult

        market = m.value ?? market
        orderbook = ob.value          // nil hides the book
        trades = tr.value ?? []
        candles = cs.value ?? []
        chartPoints = Self.downsample(candles)

        // Only surface an error if the primary (market) call failed.
        if m.value == nil { errorMessage = m.error }
        isLoading = false
    }

    /// Refetch only candles, e.g. after a timeframe change.
    func reloadCandles() async {
        guard !focusedMarketTicker.isEmpty, !seriesTicker.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        let (startTs, periodInterval) = timeframe.window(now: now)
        let client = self.client
        let series = seriesTicker
        let ticker = focusedMarketTicker
        let r = await Self.result {
            try await client.candlesticks(
                seriesTicker: series, ticker: ticker,
                startTs: startTs, endTs: now, periodInterval: periodInterval
            )
        }
        candles = r.value ?? []
        chartPoints = Self.downsample(candles)
    }

    /// Reduces candles to chart-ready points, capped at `cap` via uniform
    /// striding so the chart renders a small, stable set.
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
        // Always include the most recent point.
        if let last = raw.last, out.last?.date != last.0 {
            out.append(ChartPoint(id: out.count, date: last.0, percent: last.1))
        }
        return out
    }

    /// Switch the focused market (multi-outcome selection) and reload its data.
    func focus(marketTicker: String) async {
        guard marketTicker != focusedMarketTicker else { return }
        await load(seriesTicker: seriesTicker, marketTicker: marketTicker)
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
