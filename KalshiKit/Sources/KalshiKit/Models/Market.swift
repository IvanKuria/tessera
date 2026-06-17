import Foundation

/// A Kalshi market: a single binary (yes/no) contract within an event.
///
/// Prices arrive in two parallel forms:
///  - dollar **strings** (`yes_bid_dollars` → ``KalshiDecimal``), the 2026 model;
///  - legacy integer **cents** 1–99 (`yes_bid` → `Int`).
/// Both are surfaced so callers can use whichever the endpoint populated.
public struct Market: Codable, Sendable, Hashable, Identifiable {
    // MARK: Identity & descriptive

    public var ticker: String
    public var eventTicker: String?
    public var marketType: String?
    public var title: String?
    public var subtitle: String?
    public var yesSubTitle: String?
    public var noSubTitle: String?

    // MARK: Lifecycle

    public var status: MarketStatus

    /// Raw ISO-8601 time strings (use the matching `*Date` accessor for `Date`).
    public var openTime: String?
    public var closeTime: String?
    public var latestExpirationTime: String?

    /// Settled outcome. Optional; an empty server string decodes to `nil`.
    public var result: MarketResult?

    // MARK: Prices/sizes — dollar strings (KalshiDecimal)

    public var yesBidDollars: KalshiDecimal?
    public var yesAskDollars: KalshiDecimal?
    public var noBidDollars: KalshiDecimal?
    public var noAskDollars: KalshiDecimal?
    public var lastPriceDollars: KalshiDecimal?
    public var previousPriceDollars: KalshiDecimal?

    public var volumeFp: KalshiDecimal?
    public var volume24hFp: KalshiDecimal?
    public var openInterestFp: KalshiDecimal?
    public var liquidityDollars: KalshiDecimal?
    public var notionalValueDollars: KalshiDecimal?

    // MARK: Prices/sizes — legacy integer cents (1–99)

    public var yesBid: Int?
    public var yesAsk: Int?
    public var noBid: Int?
    public var noAsk: Int?
    public var lastPrice: Int?
    public var volume: Int?
    public var openInterest: Int?

    /// Natural identity is the market ticker.
    public var id: String { ticker }

    // MARK: Computed time accessors

    public var openDate: Date? { KalshiTime.date(fromISO: openTime) }
    public var closeDate: Date? { KalshiTime.date(fromISO: closeTime) }
    public var latestExpirationDate: Date? { KalshiTime.date(fromISO: latestExpirationTime) }

    // MARK: Custom decoding (treat empty `result` string as nil)

    private enum CodingKeys: String, CodingKey {
        case ticker, eventTicker, marketType, title, subtitle
        case yesSubTitle, noSubTitle, status
        case openTime, closeTime, latestExpirationTime, result
        case yesBidDollars, yesAskDollars, noBidDollars, noAskDollars
        case lastPriceDollars, previousPriceDollars
        case volumeFp, volume24hFp, openInterestFp, liquidityDollars, notionalValueDollars
        case yesBid, yesAsk, noBid, noAsk, lastPrice, volume, openInterest
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try c.decode(String.self, forKey: .ticker)
        eventTicker = try c.decodeIfPresent(String.self, forKey: .eventTicker)
        marketType = try c.decodeIfPresent(String.self, forKey: .marketType)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        yesSubTitle = try c.decodeIfPresent(String.self, forKey: .yesSubTitle)
        noSubTitle = try c.decodeIfPresent(String.self, forKey: .noSubTitle)
        // Tolerate a missing status: default to `.unknown` rather than throwing.
        status = ((try? c.decodeIfPresent(MarketStatus.self, forKey: .status)) ?? nil) ?? .unknown

        openTime = try c.decodeIfPresent(String.self, forKey: .openTime)
        closeTime = try c.decodeIfPresent(String.self, forKey: .closeTime)
        latestExpirationTime = try c.decodeIfPresent(String.self, forKey: .latestExpirationTime)

        // The `result` field may be absent or an empty string — both → nil.
        let rawResult = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? nil
        if let rawResult, !rawResult.isEmpty {
            result = MarketResult(rawValue: rawResult) ?? .unknown
        } else {
            result = nil
        }

        yesBidDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .yesBidDollars)
        yesAskDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .yesAskDollars)
        noBidDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .noBidDollars)
        noAskDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .noAskDollars)
        lastPriceDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .lastPriceDollars)
        previousPriceDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .previousPriceDollars)

        volumeFp = try c.decodeIfPresent(KalshiDecimal.self, forKey: .volumeFp)
        volume24hFp = try c.decodeIfPresent(KalshiDecimal.self, forKey: .volume24hFp)
        openInterestFp = try c.decodeIfPresent(KalshiDecimal.self, forKey: .openInterestFp)
        liquidityDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .liquidityDollars)
        notionalValueDollars = try c.decodeIfPresent(KalshiDecimal.self, forKey: .notionalValueDollars)

        yesBid = try c.decodeIfPresent(Int.self, forKey: .yesBid)
        yesAsk = try c.decodeIfPresent(Int.self, forKey: .yesAsk)
        noBid = try c.decodeIfPresent(Int.self, forKey: .noBid)
        noAsk = try c.decodeIfPresent(Int.self, forKey: .noAsk)
        lastPrice = try c.decodeIfPresent(Int.self, forKey: .lastPrice)
        volume = try c.decodeIfPresent(Int.self, forKey: .volume)
        openInterest = try c.decodeIfPresent(Int.self, forKey: .openInterest)
    }

    // MARK: Memberwise init (decoding is custom, so provide one explicitly)

    public init(
        ticker: String,
        eventTicker: String? = nil,
        marketType: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        yesSubTitle: String? = nil,
        noSubTitle: String? = nil,
        status: MarketStatus = .unknown,
        openTime: String? = nil,
        closeTime: String? = nil,
        latestExpirationTime: String? = nil,
        result: MarketResult? = nil,
        yesBidDollars: KalshiDecimal? = nil,
        yesAskDollars: KalshiDecimal? = nil,
        noBidDollars: KalshiDecimal? = nil,
        noAskDollars: KalshiDecimal? = nil,
        lastPriceDollars: KalshiDecimal? = nil,
        previousPriceDollars: KalshiDecimal? = nil,
        volumeFp: KalshiDecimal? = nil,
        volume24hFp: KalshiDecimal? = nil,
        openInterestFp: KalshiDecimal? = nil,
        liquidityDollars: KalshiDecimal? = nil,
        notionalValueDollars: KalshiDecimal? = nil,
        yesBid: Int? = nil,
        yesAsk: Int? = nil,
        noBid: Int? = nil,
        noAsk: Int? = nil,
        lastPrice: Int? = nil,
        volume: Int? = nil,
        openInterest: Int? = nil
    ) {
        self.ticker = ticker
        self.eventTicker = eventTicker
        self.marketType = marketType
        self.title = title
        self.subtitle = subtitle
        self.yesSubTitle = yesSubTitle
        self.noSubTitle = noSubTitle
        self.status = status
        self.openTime = openTime
        self.closeTime = closeTime
        self.latestExpirationTime = latestExpirationTime
        self.result = result
        self.yesBidDollars = yesBidDollars
        self.yesAskDollars = yesAskDollars
        self.noBidDollars = noBidDollars
        self.noAskDollars = noAskDollars
        self.lastPriceDollars = lastPriceDollars
        self.previousPriceDollars = previousPriceDollars
        self.volumeFp = volumeFp
        self.volume24hFp = volume24hFp
        self.openInterestFp = openInterestFp
        self.liquidityDollars = liquidityDollars
        self.notionalValueDollars = notionalValueDollars
        self.yesBid = yesBid
        self.yesAsk = yesAsk
        self.noBid = noBid
        self.noAsk = noAsk
        self.lastPrice = lastPrice
        self.volume = volume
        self.openInterest = openInterest
    }
}

// MARK: - Convenience computed properties

public extension Market {
    /// Best estimate of the market's implied YES probability as a `Decimal`
    /// in `0...1`. Prefers `lastPriceDollars`; falls back to the mid of the
    /// yes bid/ask (dollar strings preferred, then legacy cents/100).
    var yesProbability: Decimal? {
        if let last = lastPriceDollars { return last.value }

        if let bid = yesBidDollars?.value, let ask = yesAskDollars?.value {
            return (bid + ask) / 2
        }
        if let bid = yesBid, let ask = yesAsk {
            return (Decimal(bid) + Decimal(ask)) / 200 // cents → dollars, then mid
        }
        if let bid = yesBidDollars?.value { return bid }
        if let ask = yesAskDollars?.value { return ask }
        return nil
    }

    /// Implied YES probability as a rounded integer percent `0...100` for UI.
    var impliedPercent: Int? {
        guard let p = yesProbability else { return nil }
        let pct = NSDecimalNumber(decimal: p * 100).doubleValue
        return min(100, max(0, Int(pct.rounded())))
    }
}

/// Paged list of markets (`GET /markets`).
public struct MarketListResponse: Codable, Sendable, Hashable, CursorPaged {
    public var markets: [Market]
    public var cursor: String?

    /// `CursorPaged` items projection.
    public var items: [Market] { markets }

    public init(markets: [Market], cursor: String? = nil) {
        self.markets = markets
        self.cursor = cursor
    }
}

/// Single-market endpoint envelope (`GET /markets/{ticker}`).
public struct MarketResponse: Codable, Sendable, Hashable {
    public var market: Market

    public init(market: Market) {
        self.market = market
    }
}
