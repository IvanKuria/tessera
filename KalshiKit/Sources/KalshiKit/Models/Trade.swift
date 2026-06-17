import Foundation

/// A public trade tape entry (`GET /markets/trades`).
public struct Trade: Codable, Sendable, Hashable, Identifiable {
    public var tradeId: String?
    public var ticker: String
    /// Number of contracts traded, fixed-point string (`count_fp`, verified live).
    public var countFp: KalshiDecimal?
    /// Price paid by the YES side, dollar string (`yes_price_dollars`, verified live).
    public var yesPriceDollars: KalshiDecimal?
    /// Price paid by the NO side, dollar string (`no_price_dollars`, verified live).
    public var noPriceDollars: KalshiDecimal?
    /// Legacy integer-cents fields (kept for older responses; usually nil in 2026).
    public var count: Int?
    public var yesPrice: Int?
    public var noPrice: Int?
    /// Which side the taker (aggressor) was on.
    public var takerSide: OrderSide?
    /// Which book side the taker hit (`ask`/`bid`).
    public var takerBookSide: String?
    /// Whether this was a block trade.
    public var isBlockTrade: Bool?
    /// Raw ISO-8601 creation time (see `createdDate`).
    public var createdTime: String?

    /// Natural identity is the trade id when present, else a synthesized key.
    public var id: String { tradeId ?? "\(ticker)-\(createdTime ?? "")" }

    /// Parsed creation time.
    public var createdDate: Date? { KalshiTime.date(fromISO: createdTime) }

    public init(
        tradeId: String? = nil,
        ticker: String,
        countFp: KalshiDecimal? = nil,
        yesPriceDollars: KalshiDecimal? = nil,
        noPriceDollars: KalshiDecimal? = nil,
        count: Int? = nil,
        yesPrice: Int? = nil,
        noPrice: Int? = nil,
        takerSide: OrderSide? = nil,
        takerBookSide: String? = nil,
        isBlockTrade: Bool? = nil,
        createdTime: String? = nil
    ) {
        self.tradeId = tradeId
        self.ticker = ticker
        self.countFp = countFp
        self.yesPriceDollars = yesPriceDollars
        self.noPriceDollars = noPriceDollars
        self.count = count
        self.yesPrice = yesPrice
        self.noPrice = noPrice
        self.takerSide = takerSide
        self.takerBookSide = takerBookSide
        self.isBlockTrade = isBlockTrade
        self.createdTime = createdTime
    }
}

/// Paged list of trades (`GET /markets/trades`).
public struct TradeListResponse: Codable, Sendable, Hashable, CursorPaged {
    public var trades: [Trade]
    public var cursor: String?

    /// `CursorPaged` items projection.
    public var items: [Trade] { trades }

    public init(trades: [Trade], cursor: String? = nil) {
        self.trades = trades
        self.cursor = cursor
    }
}
