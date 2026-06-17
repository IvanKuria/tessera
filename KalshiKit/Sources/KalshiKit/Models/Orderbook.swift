import Foundation

/// A market order book (`GET /markets/{ticker}/orderbook`).
///
/// Verified shape (June 2026): the response key is `orderbook_fp`, and each side
/// (`yes_dollars` / `no_dollars`) is an array of `[price_dollars, size]` **string**
/// pairs sorted ascending by price, e.g. `[["0.8500","303.00"], …]`.
///
/// YES bids and NO bids are the two sides of one book: a resting NO bid at price
/// `p` is equivalent to an offer to sell YES at `1 − p`. ``yesAskLevels`` exposes
/// that derived sell-YES side so a unified ladder can be drawn.
public struct Orderbook: Codable, Sendable, Hashable {
    /// Resting bids to buy YES: `[priceDollars, size]` strings.
    public var yesDollars: [[String]]?
    /// Resting bids to buy NO: `[priceDollars, size]` strings.
    public var noDollars: [[String]]?

    /// A typed price level.
    public struct Level: Sendable, Hashable {
        /// Price in cents (1…99).
        public let priceCents: Int
        /// Resting size in contracts (fractional trading is supported).
        public let size: Decimal

        public init(priceCents: Int, size: Decimal) {
            self.priceCents = priceCents
            self.size = size
        }
    }

    /// Bids to buy YES (green side), ascending by price.
    public var yesBidLevels: [Level] { Self.levels(from: yesDollars) }
    /// Bids to buy NO, ascending by price.
    public var noBidLevels: [Level] { Self.levels(from: noDollars) }
    /// Derived offers to SELL YES = each NO bid at `p` mapped to a YES ask at `100 − p`.
    public var yesAskLevels: [Level] {
        noBidLevels.map { Level(priceCents: 100 - $0.priceCents, size: $0.size) }
    }

    /// Best (highest) YES bid in cents.
    public var bestYesBid: Int? { yesBidLevels.map(\.priceCents).max() }
    /// Best (lowest) YES ask in cents.
    public var bestYesAsk: Int? { yesAskLevels.map(\.priceCents).min() }

    private static func levels(from raw: [[String]]?) -> [Level] {
        guard let raw else { return [] }
        return raw.compactMap { row in
            guard row.count >= 2,
                  let price = Decimal(string: row[0], locale: Locale(identifier: "en_US_POSIX")),
                  let size = Decimal(string: row[1], locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            let cents = Int(NSDecimalNumber(decimal: price * 100).doubleValue.rounded())
            return Level(priceCents: cents, size: size)
        }
    }

    public init(yesDollars: [[String]]? = nil, noDollars: [[String]]? = nil) {
        self.yesDollars = yesDollars
        self.noDollars = noDollars
    }
}

/// Order book endpoint envelope: `{ "orderbook_fp": { "yes_dollars": …, "no_dollars": … } }`.
public struct OrderbookResponse: Codable, Sendable, Hashable {
    public var orderbookFp: Orderbook?

    /// Convenience accessor (non-optional; empty book if absent).
    public var orderbook: Orderbook { orderbookFp ?? Orderbook() }

    public init(orderbookFp: Orderbook? = nil) {
        self.orderbookFp = orderbookFp
    }
}
