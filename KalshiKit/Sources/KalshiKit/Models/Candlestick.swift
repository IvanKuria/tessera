import Foundation

/// A single candlestick / OHLC bucket for a market
/// (`GET /series/{series}/markets/{ticker}/candlesticks`).
///
/// Verified shape (June 2026): each candle nests trade-based `price` OHLC plus
/// `yes_bid`/`yes_ask` quote OHLC, all as `*_dollars` strings (0.0000–1.0000).
/// `price.close` is null in periods with no trades, so use ``probability`` which
/// falls back to the bid/ask mid for a gapless line.
public struct Candlestick: Codable, Sendable, Hashable {
    /// End of the bucket as Unix epoch **seconds** (see `endPeriodDate`).
    public var endPeriodTs: Int?
    public var openInterestFp: KalshiDecimal?
    public var volumeFp: KalshiDecimal?
    /// Trade-based OHLC (open/high/low/close/mean/previous), dollars.
    public var price: OHLC?
    /// Best-bid quote OHLC, dollars.
    public var yesBid: OHLC?
    /// Best-ask quote OHLC, dollars.
    public var yesAsk: OHLC?

    /// Open/High/Low/Close (+ mean/previous) in dollar strings.
    public struct OHLC: Codable, Sendable, Hashable {
        public var openDollars: KalshiDecimal?
        public var highDollars: KalshiDecimal?
        public var lowDollars: KalshiDecimal?
        public var closeDollars: KalshiDecimal?
        public var meanDollars: KalshiDecimal?
        public var previousDollars: KalshiDecimal?

        public init(
            openDollars: KalshiDecimal? = nil, highDollars: KalshiDecimal? = nil,
            lowDollars: KalshiDecimal? = nil, closeDollars: KalshiDecimal? = nil,
            meanDollars: KalshiDecimal? = nil, previousDollars: KalshiDecimal? = nil
        ) {
            self.openDollars = openDollars; self.highDollars = highDollars
            self.lowDollars = lowDollars; self.closeDollars = closeDollars
            self.meanDollars = meanDollars; self.previousDollars = previousDollars
        }
    }

    /// Parsed end-of-period time.
    public var endPeriodDate: Date? { KalshiTime.date(fromUnixSeconds: endPeriodTs) }

    /// Implied YES probability for this candle as a `Decimal` in `0…1`:
    /// prefers the trade close, falls back to the mid of the bid/ask close so a
    /// line chart has no gaps in periods without trades.
    public var probability: Decimal? {
        if let close = price?.closeDollars?.value { return close }
        if let bid = yesBid?.closeDollars?.value, let ask = yesAsk?.closeDollars?.value {
            return (bid + ask) / 2
        }
        return yesAsk?.closeDollars?.value ?? yesBid?.closeDollars?.value
    }

    public init(
        endPeriodTs: Int? = nil,
        openInterestFp: KalshiDecimal? = nil,
        volumeFp: KalshiDecimal? = nil,
        price: OHLC? = nil,
        yesBid: OHLC? = nil,
        yesAsk: OHLC? = nil
    ) {
        self.endPeriodTs = endPeriodTs
        self.openInterestFp = openInterestFp
        self.volumeFp = volumeFp
        self.price = price
        self.yesBid = yesBid
        self.yesAsk = yesAsk
    }
}

/// Candlesticks endpoint envelope.
public struct CandlesticksResponse: Codable, Sendable, Hashable {
    public var candlesticks: [Candlestick]
    public var cursor: String?

    public init(candlesticks: [Candlestick], cursor: String? = nil) {
        self.candlesticks = candlesticks
        self.cursor = cursor
    }
}
