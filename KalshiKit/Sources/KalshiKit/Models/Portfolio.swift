import Foundation

/// Account balance (`GET /portfolio/balance`).
public struct Balance: Codable, Sendable, Hashable {
    /// Available balance in cents.
    public var balance: Int?
    /// Available balance as a dollar string.
    public var balanceDollars: KalshiDecimal?
    /// Total portfolio value as a dollar string.
    public var portfolioValueDollars: KalshiDecimal?
    /// Last-updated time as Unix epoch **seconds** (see `updatedDate`).
    public var updatedTs: Int?

    /// Parsed update time.
    public var updatedDate: Date? { KalshiTime.date(fromUnixSeconds: updatedTs) }

    public init(
        balance: Int? = nil,
        balanceDollars: KalshiDecimal? = nil,
        portfolioValueDollars: KalshiDecimal? = nil,
        updatedTs: Int? = nil
    ) {
        self.balance = balance
        self.balanceDollars = balanceDollars
        self.portfolioValueDollars = portfolioValueDollars
        self.updatedTs = updatedTs
    }
}

/// A position in a single market (`GET /portfolio/positions`).
public struct MarketPosition: Codable, Sendable, Hashable, Identifiable {
    public var ticker: String
    /// Signed position as a fixed-point string (fractional contracts).
    public var positionFp: KalshiDecimal?
    /// Signed position in whole contracts (positive = YES, negative = NO).
    public var position: Int?
    public var marketExposureDollars: KalshiDecimal?
    public var realizedPnlDollars: KalshiDecimal?
    public var feesPaidDollars: KalshiDecimal?

    /// Natural identity is the market ticker.
    public var id: String { ticker }

    public init(
        ticker: String,
        positionFp: KalshiDecimal? = nil,
        position: Int? = nil,
        marketExposureDollars: KalshiDecimal? = nil,
        realizedPnlDollars: KalshiDecimal? = nil,
        feesPaidDollars: KalshiDecimal? = nil
    ) {
        self.ticker = ticker
        self.positionFp = positionFp
        self.position = position
        self.marketExposureDollars = marketExposureDollars
        self.realizedPnlDollars = realizedPnlDollars
        self.feesPaidDollars = feesPaidDollars
    }
}

/// An aggregated position across an event's markets.
public struct EventPosition: Codable, Sendable, Hashable, Identifiable {
    public var eventTicker: String
    public var eventExposureDollars: KalshiDecimal?
    public var realizedPnlDollars: KalshiDecimal?
    public var feesPaidDollars: KalshiDecimal?
    public var totalCostDollars: KalshiDecimal?

    /// Natural identity is the event ticker.
    public var id: String { eventTicker }

    public init(
        eventTicker: String,
        eventExposureDollars: KalshiDecimal? = nil,
        realizedPnlDollars: KalshiDecimal? = nil,
        feesPaidDollars: KalshiDecimal? = nil,
        totalCostDollars: KalshiDecimal? = nil
    ) {
        self.eventTicker = eventTicker
        self.eventExposureDollars = eventExposureDollars
        self.realizedPnlDollars = realizedPnlDollars
        self.feesPaidDollars = feesPaidDollars
        self.totalCostDollars = totalCostDollars
    }
}

/// Positions endpoint envelope (`GET /portfolio/positions`).
///
/// Conforms to `CursorPaged` over market positions (the primary collection).
public struct PositionsResponse: Codable, Sendable, Hashable, CursorPaged {
    public var marketPositions: [MarketPosition]?
    public var eventPositions: [EventPosition]?
    public var cursor: String?

    /// `CursorPaged` items projection (market positions).
    public var items: [MarketPosition] { marketPositions ?? [] }

    public init(
        marketPositions: [MarketPosition]? = nil,
        eventPositions: [EventPosition]? = nil,
        cursor: String? = nil
    ) {
        self.marketPositions = marketPositions
        self.eventPositions = eventPositions
        self.cursor = cursor
    }
}
