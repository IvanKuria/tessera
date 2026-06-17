import Foundation

/// The shared, read-only market-data layer for the app.
///
/// `MarketDataService` owns a single keyless ``KalshiClient`` and exposes thin
/// async pass-through methods for the market-data endpoints that do not require
/// credentials. App stores and the (future) widget extension share one instance
/// of this actor rather than each constructing their own client, so they all
/// benefit from the same `URLSession` connection reuse and a single point of
/// configuration.
///
/// All methods here are keyless reads; for authenticated portfolio/trading
/// calls use ``KalshiClient`` directly with a configured ``RequestSigning``.
///
/// ```swift
/// let data = MarketDataService(environment: .production)
/// let markets = try await data.markets(status: "open")
/// ```
public actor MarketDataService {
    /// The single keyless client backing every call.
    private let client: KalshiClient

    /// Creates a service backed by a fresh keyless client.
    ///
    /// - Parameter environment: which Kalshi backend to read from. Defaults to
    ///   `.production`.
    public init(environment: KalshiEnvironment = .production) {
        self.client = KalshiClient(environment: environment)
    }

    // MARK: - Events

    /// Lists events. See ``KalshiClient/events(status:seriesTicker:withNestedMarkets:limit:cursor:)``.
    public func events(
        status: String? = nil,
        seriesTicker: String? = nil,
        withNestedMarkets: Bool = false,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> EventListResponse {
        try await client.events(
            status: status,
            seriesTicker: seriesTicker,
            withNestedMarkets: withNestedMarkets,
            limit: limit,
            cursor: cursor
        )
    }

    // MARK: - Markets

    /// Lists markets. See ``KalshiClient/markets(status:eventTicker:seriesTicker:tickers:limit:cursor:)``.
    public func markets(
        status: String? = nil,
        eventTicker: String? = nil,
        seriesTicker: String? = nil,
        tickers: [String]? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> MarketListResponse {
        try await client.markets(
            status: status,
            eventTicker: eventTicker,
            seriesTicker: seriesTicker,
            tickers: tickers,
            limit: limit,
            cursor: cursor
        )
    }

    /// Fetches a single market by ticker. See ``KalshiClient/market(_:)``.
    public func market(_ ticker: String) async throws -> Market {
        try await client.market(ticker)
    }

    // MARK: - Orderbook

    /// Fetches the orderbook for a market. See ``KalshiClient/orderbook(ticker:depth:)``.
    public func orderbook(ticker: String, depth: Int? = nil) async throws -> Orderbook {
        try await client.orderbook(ticker: ticker, depth: depth)
    }

    // MARK: - Candlesticks

    /// Fetches candlesticks for a market. See
    /// ``KalshiClient/candlesticks(seriesTicker:ticker:startTs:endTs:periodInterval:)``.
    public func candlesticks(
        seriesTicker: String,
        ticker: String,
        startTs: Int,
        endTs: Int,
        periodInterval: Int
    ) async throws -> [Candlestick] {
        try await client.candlesticks(
            seriesTicker: seriesTicker,
            ticker: ticker,
            startTs: startTs,
            endTs: endTs,
            periodInterval: periodInterval
        )
    }

    // MARK: - Exchange

    /// Returns the exchange status. See ``KalshiClient/exchangeStatus()``.
    public func exchangeStatus() async throws -> ExchangeStatus {
        try await client.exchangeStatus()
    }

    // MARK: - Trades

    /// Lists public trades. See ``KalshiClient/trades(ticker:limit:cursor:)``.
    public func trades(
        ticker: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> TradeListResponse {
        try await client.trades(ticker: ticker, limit: limit, cursor: cursor)
    }
}
