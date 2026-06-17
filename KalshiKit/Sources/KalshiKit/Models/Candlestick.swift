import Foundation

/// A single candlestick / OHLC bucket for a market
/// (`GET /series/{series}/markets/{ticker}/candlesticks`).
///
/// Kalshi's candlestick payload nests price OHLC under sub-objects whose exact
/// shape varies by version. To stay forgiving, every field is optional and the
/// model flattens the most common fields; unknown extra keys are ignored.
public struct Candlestick: Codable, Sendable, Hashable {
    /// End of the bucket period as Unix epoch **seconds** (see `endPeriodDate`).
    public var endPeriodTs: Int?

    /// OHLC, in cents.
    public var open: Int?
    public var high: Int?
    public var low: Int?
    public var close: Int?

    public var yesBid: Int?
    public var yesAsk: Int?
    public var volume: Int?
    public var openInterest: Int?

    /// Parsed end-of-period time.
    public var endPeriodDate: Date? { KalshiTime.date(fromUnixSeconds: endPeriodTs) }

    private enum CodingKeys: String, CodingKey {
        case endPeriodTs
        case open, high, low, close
        case yesBid, yesAsk, volume, openInterest
        case price
    }

    /// Nested OHLC container some payloads use (`price.open`, …).
    private struct OHLC: Codable {
        var open: Int?
        var high: Int?
        var low: Int?
        var close: Int?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func optInt(_ key: CodingKeys) -> Int? {
            (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil
        }

        endPeriodTs = optInt(.endPeriodTs)

        // Prefer top-level OHLC; fall back to a nested `price` object.
        let nested: OHLC? = (try? c.decodeIfPresent(OHLC.self, forKey: .price)) ?? nil
        open = optInt(.open) ?? nested?.open
        high = optInt(.high) ?? nested?.high
        low = optInt(.low) ?? nested?.low
        close = optInt(.close) ?? nested?.close

        yesBid = optInt(.yesBid)
        yesAsk = optInt(.yesAsk)
        volume = optInt(.volume)
        openInterest = optInt(.openInterest)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(endPeriodTs, forKey: .endPeriodTs)
        try c.encodeIfPresent(open, forKey: .open)
        try c.encodeIfPresent(high, forKey: .high)
        try c.encodeIfPresent(low, forKey: .low)
        try c.encodeIfPresent(close, forKey: .close)
        try c.encodeIfPresent(yesBid, forKey: .yesBid)
        try c.encodeIfPresent(yesAsk, forKey: .yesAsk)
        try c.encodeIfPresent(volume, forKey: .volume)
        try c.encodeIfPresent(openInterest, forKey: .openInterest)
    }

    public init(
        endPeriodTs: Int? = nil,
        open: Int? = nil,
        high: Int? = nil,
        low: Int? = nil,
        close: Int? = nil,
        yesBid: Int? = nil,
        yesAsk: Int? = nil,
        volume: Int? = nil,
        openInterest: Int? = nil
    ) {
        self.endPeriodTs = endPeriodTs
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.yesBid = yesBid
        self.yesAsk = yesAsk
        self.volume = volume
        self.openInterest = openInterest
    }
}

/// Candlesticks endpoint envelope. No cursor is documented, but one is accepted
/// defensively in case the API adds pagination.
public struct CandlesticksResponse: Codable, Sendable, Hashable {
    public var candlesticks: [Candlestick]
    public var cursor: String?

    public init(candlesticks: [Candlestick], cursor: String? = nil) {
        self.candlesticks = candlesticks
        self.cursor = cursor
    }
}
