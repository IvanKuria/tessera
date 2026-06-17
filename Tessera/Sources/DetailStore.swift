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

        /// Candle window: fetch a finer native interval, then aggregate to
        /// `bucketMinutes` for a denser candlestick chart (~60–180 bars) than the
        /// line chart needs. Independent of `window(now:)` so the line path is untouched.
        func candleWindow(now: Int) -> (startTs: Int, periodInterval: Int, bucketMinutes: Int) {
            switch self {
            case .h1:  return (now - 3_600, 1, 1)            // 60 × 1-min
            case .d1:  return (now - 86_400, 1, 15)          // 1440 × 1-min → 15-min ≈ 96
            case .w1:  return (now - 604_800, 60, 120)       // 168 × hourly → 2h ≈ 84
            case .m1:  return (now - 2_592_000, 60, 240)     // 720 × hourly → 4h ≈ 180
            case .all: return (now - 31_536_000, 1_440, 1_440) // daily passthrough
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
    /// Candlestick bars for the focused single market (candle chart mode).
    private(set) var focusedCandles: [CandleVM] = []
    private(set) var orderbook: Orderbook?
    private(set) var trades: [Trade] = []

    var timeframe: Timeframe = .all
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // Live feed (WebSocket) — populated when signed in; views prefer these.
    private(set) var isLive = false
    private(set) var liveLastCents: Int?
    private(set) var liveYesAskCents: Int?
    private(set) var liveNoAskCents: Int?

    private let client = KalshiClient(environment: .production)
    private var socket: KalshiSocket?
    private var liveTask: Task<Void, Never>?
    private var lastBookRefresh = Date(timeIntervalSince1970: 0)

    /// Initial load: focused-market detail + the chart series, concurrently.
    func load(event: EventVM) async {
        self.event = event
        seriesTicker = event.seriesTicker
        focusedMarketTicker = event.topOutcome?.id ?? ""
        isLoading = true
        errorMessage = nil
        async let detail: Void = loadFocusedDetail(marketTicker: focusedMarketTicker)
        async let chart: Void = loadChartSeries()
        async let candles: Void = loadFocusedCandles()
        _ = await (detail, chart, candles)
        isLoading = false
    }

    /// Reloads just the focused market's quote/book/trades (multi-outcome selection).
    func focus(marketTicker: String) async {
        guard marketTicker != focusedMarketTicker, !marketTicker.isEmpty else { return }
        focusedMarketTicker = marketTicker
        liveLastCents = nil; liveYesAskCents = nil; liveNoAskCents = nil
        async let detail: Void = loadFocusedDetail(marketTicker: marketTicker)
        async let candles: Void = loadFocusedCandles()
        _ = await (detail, candles)
        if let socket { await socket.subscribe(to: [.ticker, .trade], markets: [marketTicker]) }
    }

    /// Fetches + aggregates candlesticks for the focused market into chart bars.
    func loadFocusedCandles() async {
        guard !focusedMarketTicker.isEmpty, !seriesTicker.isEmpty else { focusedCandles = []; return }
        let now = Int(Date().timeIntervalSince1970)
        let (startTs, periodInterval, bucketMinutes) = timeframe.candleWindow(now: now)
        let client = self.client
        let series = seriesTicker
        let ticker = focusedMarketTicker
        let raw = (try? await client.candlesticks(
            seriesTicker: series, ticker: ticker,
            startTs: startTs, endTs: now, periodInterval: periodInterval
        )) ?? []
        focusedCandles = Self.prepareCandles(raw, bucketMinutes: bucketMinutes)
    }

    /// Aggregates raw candles (reusing the SDK's tested bucketer) and maps to
    /// chart-ready `CandleVM`s in cents, carrying the last close through no-trade gaps.
    nonisolated static func prepareCandles(_ raw: [Candlestick], bucketMinutes: Int) -> [CandleVM] {
        let aggregated = CandleAggregation.aggregate(raw, bucketMinutes: bucketMinutes)
            .sorted { ($0.endPeriodTs ?? 0) < ($1.endPeriodTs ?? 0) }

        func cents(_ value: KalshiDecimal?) -> Double? {
            value.map { NSDecimalNumber(decimal: $0.value * 100).doubleValue }
        }

        var result: [CandleVM] = []
        var lastClose: Double?
        for candle in aggregated {
            guard let ts = candle.endPeriodTs else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(ts))
            let bid = cents(candle.yesBid?.closeDollars)
            let ask = cents(candle.yesAsk?.closeDollars)
            let mid: Double? = (bid != nil && ask != nil) ? (bid! + ask!) / 2 : (bid ?? ask)

            // Trade OHLC if there were trades; else carry forward the last close
            // (flat doji) or fall back to the bid/ask mid for the very first bar.
            guard let close = cents(candle.price?.closeDollars) ?? lastClose ?? mid else { continue }
            let open = cents(candle.price?.openDollars) ?? lastClose ?? close
            let high = cents(candle.price?.highDollars) ?? max(open, close)
            let low = cents(candle.price?.lowDollars) ?? min(open, close)
            let volume = candle.volumeFp?.doubleValue ?? 0

            result.append(CandleVM(id: result.count, date: date,
                                   open: open, high: high, low: low, close: close,
                                   volume: volume, yesBid: bid, yesAsk: ask))
            lastClose = close
        }
        return result
    }

    // MARK: - Live WebSocket feed

    /// Opens an authenticated socket (requires a signer) and streams live ticker
    /// + trades for the focused market. No-op when not signed in — the screen
    /// then stays on its REST snapshot.
    func startLive(signer: (any RequestSigning)?, environment: KalshiEnvironment) async {
        guard let signer, socket == nil, !focusedMarketTicker.isEmpty else { return }
        let socket = KalshiSocket(environment: environment, signer: signer)
        self.socket = socket
        let stream = await socket.events()
        await socket.connect()
        await socket.subscribe(to: [.ticker, .trade], markets: [focusedMarketTicker])
        liveTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                await self.handle(live: event)
            }
        }
    }

    /// Tears down the live socket (call on disappear).
    func stopLive() {
        liveTask?.cancel(); liveTask = nil
        let closing = socket
        socket = nil
        isLive = false
        liveLastCents = nil; liveYesAskCents = nil; liveNoAskCents = nil
        Task { await closing?.disconnect() }
    }

    private func handle(live event: SocketEvent) {
        switch event {
        case .connected:
            isLive = true
        case .disconnected:
            isLive = false
        case .ticker(let t):
            guard t.marketTicker == focusedMarketTicker else { return }
            if let c = cents(t.priceDollars) ?? t.price { liveLastCents = c }
            if let c = cents(t.yesAskDollars) ?? t.yesAsk { liveYesAskCents = c }
            // NO ask = 100 − best YES bid.
            if let yb = cents(t.yesBidDollars) ?? t.yesBid { liveNoAskCents = 100 - yb }
        case .trade(let t):
            guard t.marketTicker == focusedMarketTicker else { return }
            prepend(liveTrade: t)
            refreshBookThrottled()
        default:
            break
        }
    }

    private func prepend(liveTrade t: TradeUpdate) {
        let trade = Trade(
            tradeId: "live-\(trades.count)-\(focusedMarketTicker)",
            ticker: t.marketTicker ?? focusedMarketTicker,
            countFp: t.countFp,
            yesPriceDollars: t.yesPriceDollars,
            noPriceDollars: t.noPriceDollars,
            count: t.count,
            takerSide: t.takerSide,
            createdTime: ISO8601DateFormatter().string(from: Date())
        )
        trades.insert(trade, at: 0)
        if trades.count > 40 { trades.removeLast(trades.count - 40) }
    }

    private func refreshBookThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastBookRefresh) > 2 else { return }
        lastBookRefresh = now
        let client = self.client
        let ticker = focusedMarketTicker
        Task { [weak self] in
            guard let book = try? await client.orderbook(ticker: ticker, depth: 12) else { return }
            await self?.setOrderbook(book)
        }
    }

    private func setOrderbook(_ book: Orderbook) { orderbook = book }

    private func cents(_ value: KalshiDecimal?) -> Int? {
        guard let value else { return nil }
        return Int(NSDecimalNumber(decimal: value.value * 100).doubleValue.rounded())
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
        let chosen = Array(event.outcomes.prefix(event.isBinary ? 1 : 4))

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
