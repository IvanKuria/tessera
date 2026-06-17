import Foundation

/// A market order book (`GET /markets/{ticker}/orderbook`).
///
/// Each side is an array of `[priceCents, sizeContracts]` pairs. The wire format
/// uses bare integer arrays; ``Level`` provides a typed projection.
public struct Orderbook: Codable, Sendable, Hashable {
    /// Raw YES side levels: each inner array is `[priceCents, sizeContracts]`.
    public var yes: [[Int]]?
    /// Raw NO side levels: each inner array is `[priceCents, sizeContracts]`.
    public var no: [[Int]]?

    /// A typed order-book price level.
    public struct Level: Sendable, Hashable {
        public let priceCents: Int
        public let size: Int

        public init(priceCents: Int, size: Int) {
            self.priceCents = priceCents
            self.size = size
        }
    }

    /// Typed YES levels, skipping any malformed (non-pair) rows.
    public var yesLevels: [Level] { Orderbook.levels(from: yes) }
    /// Typed NO levels, skipping any malformed (non-pair) rows.
    public var noLevels: [Level] { Orderbook.levels(from: no) }

    private static func levels(from raw: [[Int]]?) -> [Level] {
        guard let raw else { return [] }
        return raw.compactMap { row in
            guard row.count >= 2 else { return nil }
            return Level(priceCents: row[0], size: row[1])
        }
    }

    public init(yes: [[Int]]? = nil, no: [[Int]]? = nil) {
        self.yes = yes
        self.no = no
    }
}

/// Order book endpoint envelope.
public struct OrderbookResponse: Codable, Sendable, Hashable {
    public var orderbook: Orderbook

    public init(orderbook: Orderbook) {
        self.orderbook = orderbook
    }
}
