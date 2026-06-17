import Foundation

/// A settled-market outcome for the account (`GET /portfolio/settlements`).
///
/// Authenticated endpoint. Modeled defensively: every field beyond the ticker is
/// optional and decoding is tolerant, since the exact wire shape has not been
/// verified live.
public struct Settlement: Codable, Sendable, Hashable, Identifiable {
    public var ticker: String
    /// Settled outcome (e.g. `"yes"`, `"no"`, `"void"`). Left as a raw string
    /// since the field may be empty or carry values this SDK does not model.
    public var marketResult: String?
    /// Number of YES contracts held at settlement.
    public var yesCount: Int?
    /// Number of NO contracts held at settlement.
    public var noCount: Int?
    /// Settlement revenue. The wire `revenue` may be an integer-cents value or a
    /// dollar string; `KalshiDecimal` tolerates both.
    public var revenueDollars: KalshiDecimal?
    /// Total cost of the YES position, dollar string.
    public var yesTotalCostDollars: KalshiDecimal?
    /// Total cost of the NO position, dollar string.
    public var noTotalCostDollars: KalshiDecimal?
    /// Raw ISO-8601 settlement time (see `settledDate`).
    public var settledTime: String?

    /// Natural identity is a synthesized ticker/time key.
    public var id: String { "\(ticker)-\(settledTime ?? "")" }

    /// Parsed settlement time.
    public var settledDate: Date? { KalshiTime.date(fromISO: settledTime) }

    public init(
        ticker: String,
        marketResult: String? = nil,
        yesCount: Int? = nil,
        noCount: Int? = nil,
        revenueDollars: KalshiDecimal? = nil,
        yesTotalCostDollars: KalshiDecimal? = nil,
        noTotalCostDollars: KalshiDecimal? = nil,
        settledTime: String? = nil
    ) {
        self.ticker = ticker
        self.marketResult = marketResult
        self.yesCount = yesCount
        self.noCount = noCount
        self.revenueDollars = revenueDollars
        self.yesTotalCostDollars = yesTotalCostDollars
        self.noTotalCostDollars = noTotalCostDollars
        self.settledTime = settledTime
    }

    /// Keys reflect the snake_case wire form **after** `.convertFromSnakeCase`.
    /// `revenue` is the bare wire key for the settlement revenue; `revenueDollars`
    /// (`revenue_dollars`) is accepted as an alias.
    private enum CodingKeys: String, CodingKey {
        case ticker
        case marketResult
        case yesCount
        case noCount
        case revenue
        case revenueDollars
        case yesTotalCostDollars
        case noTotalCostDollars
        case settledTime
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try c.decodeIfPresent(String.self, forKey: .ticker) ?? ""
        marketResult = try c.decodeIfPresent(String.self, forKey: .marketResult)
        yesCount = try c.decodeIfPresent(Int.self, forKey: .yesCount)
        noCount = try c.decodeIfPresent(Int.self, forKey: .noCount)
        // Accept either `revenue` or `revenue_dollars`.
        let revenue = try c.decodeIfPresent(KalshiDecimal.self, forKey: .revenue)
        let revenueDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .revenueDollars)
        self.revenueDollars = revenueDollars ?? revenue
        yesTotalCostDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .yesTotalCostDollars)
        noTotalCostDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .noTotalCostDollars)
        settledTime = try c.decodeIfPresent(String.self, forKey: .settledTime)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ticker, forKey: .ticker)
        try c.encodeIfPresent(marketResult, forKey: .marketResult)
        try c.encodeIfPresent(yesCount, forKey: .yesCount)
        try c.encodeIfPresent(noCount, forKey: .noCount)
        try c.encodeIfPresent(revenueDollars, forKey: .revenueDollars)
        try c.encodeIfPresent(yesTotalCostDollars, forKey: .yesTotalCostDollars)
        try c.encodeIfPresent(noTotalCostDollars, forKey: .noTotalCostDollars)
        try c.encodeIfPresent(settledTime, forKey: .settledTime)
    }
}

/// Paged list of settlements (`GET /portfolio/settlements`).
public struct SettlementsResponse: Codable, Sendable, Hashable, CursorPaged {
    public var settlements: [Settlement]
    public var cursor: String?

    /// `CursorPaged` items projection.
    public var items: [Settlement] { settlements }

    public init(settlements: [Settlement], cursor: String? = nil) {
        self.settlements = settlements
        self.cursor = cursor
    }
}
