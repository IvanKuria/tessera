import Foundation

/// Internal wrapper for the `GET /series` response, which Kalshi returns as
/// `{"series": [...]}`. Not part of the public API; `series(...)` returns the
/// unwrapped array.
private struct SeriesListWrapper: Decodable, Sendable {
    let series: [Series]
}

/// Internal wrapper for the `GET /events/{ticker}` response (`{"event": ...}`).
private struct EventWrapper: Decodable, Sendable {
    let event: Event
}

public extension KalshiClient {
    // MARK: - Series

    /// Lists series, optionally filtered by category and/or tags.
    ///
    /// Unwraps Kalshi's `{"series": [...]}` envelope and returns the array.
    /// Keyless (no signer required).
    func series(category: String? = nil, tags: String? = nil) async throws -> [Series] {
        var query: [URLQueryItem] = []
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        if let tags { query.append(URLQueryItem(name: "tags", value: tags)) }

        let wrapper: SeriesListWrapper = try await send(
            method: .get,
            path: "/series",
            query: query,
            authenticated: false
        )
        return wrapper.series
    }

    // MARK: - Events

    /// Lists events. Keyless.
    ///
    /// - Parameters:
    ///   - status: filter by status (e.g. `"open"`).
    ///   - seriesTicker: scope to a single series.
    ///   - withNestedMarkets: include each event's markets inline.
    ///   - limit: page size.
    ///   - cursor: pagination cursor.
    func events(
        status: String? = nil,
        seriesTicker: String? = nil,
        withNestedMarkets: Bool = false,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> EventListResponse {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        if let seriesTicker { query.append(URLQueryItem(name: "series_ticker", value: seriesTicker)) }
        if withNestedMarkets { query.append(URLQueryItem(name: "with_nested_markets", value: "true")) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/events",
            query: query,
            authenticated: false
        )
    }

    /// Fetches a single event by ticker. Unwraps `{"event": ...}`. Keyless.
    func event(_ ticker: String) async throws -> Event {
        let wrapper: EventWrapper = try await send(
            method: .get,
            path: "/events/\(ticker)",
            authenticated: false
        )
        return wrapper.event
    }

    // MARK: - Markets

    /// Lists markets. Keyless.
    ///
    /// - Parameters:
    ///   - status: filter by status (e.g. `"open"`).
    ///   - eventTicker: scope to an event.
    ///   - seriesTicker: scope to a series.
    ///   - tickers: explicit market tickers (joined as a CSV `tickers=` query value).
    ///   - limit: page size.
    ///   - cursor: pagination cursor.
    func markets(
        status: String? = nil,
        eventTicker: String? = nil,
        seriesTicker: String? = nil,
        tickers: [String]? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> MarketListResponse {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        if let eventTicker { query.append(URLQueryItem(name: "event_ticker", value: eventTicker)) }
        if let seriesTicker { query.append(URLQueryItem(name: "series_ticker", value: seriesTicker)) }
        if let tickers, !tickers.isEmpty {
            query.append(URLQueryItem(name: "tickers", value: tickers.joined(separator: ",")))
        }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/markets",
            query: query,
            authenticated: false
        )
    }

    /// Fetches a single market by ticker. Unwraps ``MarketResponse``. Keyless.
    func market(_ ticker: String) async throws -> Market {
        let response: MarketResponse = try await send(
            method: .get,
            path: "/markets/\(ticker)",
            authenticated: false
        )
        return response.market
    }

    // MARK: - Trades

    /// Lists public trades. Keyless. (Path: `/markets/trades`.)
    ///
    /// - Parameters:
    ///   - ticker: scope to a single market.
    ///   - limit: page size.
    ///   - cursor: pagination cursor.
    func trades(
        ticker: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> TradeListResponse {
        var query: [URLQueryItem] = []
        if let ticker { query.append(URLQueryItem(name: "ticker", value: ticker)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/markets/trades",
            query: query,
            authenticated: false
        )
    }

    // MARK: - Candlesticks

    /// Fetches candlesticks for a market within `[startTs, endTs]`. Keyless.
    ///
    /// Path: `/series/{seriesTicker}/markets/{ticker}/candlesticks`. Unwraps
    /// ``CandlesticksResponse`` and returns the array.
    ///
    /// - Parameters:
    ///   - seriesTicker: the series the market belongs to.
    ///   - ticker: the market ticker.
    ///   - startTs: inclusive start (Unix seconds).
    ///   - endTs: inclusive end (Unix seconds).
    ///   - periodInterval: candle period in minutes (e.g. 1, 60, 1440).
    func candlesticks(
        seriesTicker: String,
        ticker: String,
        startTs: Int,
        endTs: Int,
        periodInterval: Int
    ) async throws -> [Candlestick] {
        let query = [
            URLQueryItem(name: "start_ts", value: String(startTs)),
            URLQueryItem(name: "end_ts", value: String(endTs)),
            URLQueryItem(name: "period_interval", value: String(periodInterval)),
        ]

        let response: CandlesticksResponse = try await send(
            method: .get,
            path: "/series/\(seriesTicker)/markets/\(ticker)/candlesticks",
            query: query,
            authenticated: false
        )
        return response.candlesticks
    }

    // MARK: - Exchange

    /// Returns the exchange status (trading/active windows). Keyless.
    /// Path: `/exchange/status`.
    func exchangeStatus() async throws -> ExchangeStatus {
        try await send(
            method: .get,
            path: "/exchange/status",
            authenticated: false
        )
    }

    // MARK: - Orderbook

    /// Fetches the orderbook for a market. Unwraps ``OrderbookResponse``.
    ///
    /// Path: `/markets/{ticker}/orderbook`. Sends auth headers **if** a signer is
    /// configured, but attempts the call keyless otherwise.
    ///
    /// - Parameter depth: optional max number of price levels per side.
    func orderbook(ticker: String, depth: Int? = nil) async throws -> Orderbook {
        var query: [URLQueryItem] = []
        if let depth { query.append(URLQueryItem(name: "depth", value: String(depth))) }

        // VERIFY: orderbook auth requirement — docs conflict on whether this
        // endpoint requires authentication. We pass `authenticated: false` so the
        // transport signs only when a signer is present and otherwise tries keyless.
        let response: OrderbookResponse = try await send(
            method: .get,
            path: "/markets/\(ticker)/orderbook",
            query: query,
            authenticated: false
        )
        return response.orderbook
    }
}
