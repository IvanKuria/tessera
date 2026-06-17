import Foundation

/// A single executed trade against the account (`GET /portfolio/fills`).
///
/// Authenticated endpoint. Modeled defensively: every field is optional and
/// decoding is tolerant, since the exact wire shape has not been verified live.
public struct Fill: Codable, Sendable, Hashable, Identifiable {
    /// Server fill id. The wire key is `fill_id`; some responses use `trade_id`
    /// instead, so the custom decoder accepts either.
    public var fillId: String?
    public var orderId: String?
    public var ticker: String
    public var side: OrderSide?
    public var action: OrderAction?
    /// Number of contracts filled (legacy integer form).
    public var count: Int?
    /// Number of contracts filled, fixed-point string (`count_fp`).
    public var countFp: KalshiDecimal?
    /// Price paid by the YES side, dollar string (`yes_price_dollars`).
    public var yesPriceDollars: KalshiDecimal?
    /// Price paid by the NO side, dollar string (`no_price_dollars`).
    public var noPriceDollars: KalshiDecimal?
    /// Whether the account was the taker (aggressor) on this fill.
    public var isTaker: Bool?
    /// Raw ISO-8601 creation time (see `createdDate`).
    public var createdTime: String?

    /// Natural identity is the fill id when present, else a synthesized key.
    public var id: String { fillId ?? "\(ticker)-\(createdTime ?? "")" }

    /// Parsed creation time.
    public var createdDate: Date? { KalshiTime.date(fromISO: createdTime) }

    public init(
        fillId: String? = nil,
        orderId: String? = nil,
        ticker: String,
        side: OrderSide? = nil,
        action: OrderAction? = nil,
        count: Int? = nil,
        countFp: KalshiDecimal? = nil,
        yesPriceDollars: KalshiDecimal? = nil,
        noPriceDollars: KalshiDecimal? = nil,
        isTaker: Bool? = nil,
        createdTime: String? = nil
    ) {
        self.fillId = fillId
        self.orderId = orderId
        self.ticker = ticker
        self.side = side
        self.action = action
        self.count = count
        self.countFp = countFp
        self.yesPriceDollars = yesPriceDollars
        self.noPriceDollars = noPriceDollars
        self.isTaker = isTaker
        self.createdTime = createdTime
    }

    /// Keys reflect the snake_case wire form **after** `.convertFromSnakeCase`
    /// has mapped them to camelCase. `tradeId` is an accepted alias for `fillId`.
    private enum CodingKeys: String, CodingKey {
        case fillId
        case tradeId
        case orderId
        case ticker
        case side
        case action
        case count
        case countFp
        case yesPriceDollars
        case noPriceDollars
        case isTaker
        case createdTime
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Accept either `fill_id` or `trade_id` for the fill identifier.
        let fill = try c.decodeIfPresent(String.self, forKey: .fillId)
        let trade = try c.decodeIfPresent(String.self, forKey: .tradeId)
        fillId = fill ?? trade
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId)
        ticker = try c.decodeIfPresent(String.self, forKey: .ticker) ?? ""
        side = try c.decodeIfPresent(OrderSide.self, forKey: .side)
        action = try c.decodeIfPresent(OrderAction.self, forKey: .action)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        countFp = try c.decodeIfPresent(KalshiDecimal.self, forKey: .countFp)
        yesPriceDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .yesPriceDollars)
        noPriceDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .noPriceDollars)
        isTaker = try c.decodeIfPresent(Bool.self, forKey: .isTaker)
        createdTime = try c.decodeIfPresent(String.self, forKey: .createdTime)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fillId, forKey: .fillId)
        try c.encodeIfPresent(orderId, forKey: .orderId)
        try c.encode(ticker, forKey: .ticker)
        try c.encodeIfPresent(side, forKey: .side)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(count, forKey: .count)
        try c.encodeIfPresent(countFp, forKey: .countFp)
        try c.encodeIfPresent(yesPriceDollars, forKey: .yesPriceDollars)
        try c.encodeIfPresent(noPriceDollars, forKey: .noPriceDollars)
        try c.encodeIfPresent(isTaker, forKey: .isTaker)
        try c.encodeIfPresent(createdTime, forKey: .createdTime)
    }
}

/// Paged list of fills (`GET /portfolio/fills`).
public struct FillsResponse: Codable, Sendable, Hashable, CursorPaged {
    public var fills: [Fill]
    public var cursor: String?

    /// `CursorPaged` items projection.
    public var items: [Fill] { fills }

    public init(fills: [Fill], cursor: String? = nil) {
        self.fills = fills
        self.cursor = cursor
    }
}
