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
        func window(now: Int) -> (startTs: Int, periodInterval: Int) {
            switch self {
            case .h1:  return (now - 3_600, 1)
            case .d1:  return (now - 86_400, 1)
            case .w1:  return (now - 604_800, 60)
            case .m1:  return (now - 2_592_000, 60)
            case .all: return (now - 31_536_000, 1_440)
            }
        }
    }

    private(set) var focusedMarketTicker: String = ""
    private(set) var seriesTicker: String = ""

    private(set) var market: Market?
    private(set) var candles: [Candlestick] = []
    private(set) var orderbook: Orderbook?
    private(set) var trades: [Trade] = []

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
