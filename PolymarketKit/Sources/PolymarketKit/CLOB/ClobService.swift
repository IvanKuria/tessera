import Foundation

// MARK: - Models

/// One price level in a CLOB order book. `price` is a probability in `0...1`.
public struct PMLevel: Sendable, Hashable {
    public let price: Decimal
    public let size: Decimal

    public init(price: Decimal, size: Decimal) {
        self.price = price
        self.size = size
    }
}

/// A CLOB order book for one outcome token.
///
/// Polymarket returns bids in **ascending** price order in observed samples, so
/// ``bestBid`` and ``bestAsk`` are computed defensively via `max`/`min` rather
/// than assuming a sort order.
public struct PMOrderbook: Sendable, Hashable {
    public let bids: [PMLevel]
    public let asks: [PMLevel]

    public init(bids: [PMLevel], asks: [PMLevel]) {
        self.bids = bids
        self.asks = asks
    }

    /// Highest bid price (best price a buyer is offering).
    public var bestBid: Decimal? { bids.map(\.price).max() }
    /// Lowest ask price (best price a seller is offering).
    public var bestAsk: Decimal? { asks.map(\.price).min() }
}

/// Order side for a price query.
public enum PMSide: String, Sendable {
    case buy
    case sell
}

// MARK: - Wire DTOs

private struct LevelDTO: Decodable {
    let price: PMDecimal
    let size: PMDecimal
}

private struct BookDTO: Decodable {
    let bids: [LevelDTO]
    let asks: [LevelDTO]
}

extension PMOrderbook {
    /// Decodes a CLOB `/book` JSON payload into a ``PMOrderbook``. Exposed at
    /// `internal` visibility so tests can exercise the same decode + mapping
    /// path the live ``ClobService/book(tokenID:)`` call uses.
    static func decode(from data: Data) throws -> PMOrderbook {
        let dto = try PMJSON.decoder.decode(BookDTO.self, from: data)
        return PMOrderbook(
            bids: dto.bids.map { PMLevel(price: $0.price.value, size: $0.size.value) },
            asks: dto.asks.map { PMLevel(price: $0.price.value, size: $0.size.value) }
        )
    }
}

private struct PriceDTO: Decodable {
    let price: PMDecimal
}

private struct MidDTO: Decodable {
    let mid: PMDecimal
}

// MARK: - Service

/// Read-only client for Polymarket's CLOB order-book API.
public struct ClobService: Sendable {
    let client: PMClient

    public init(client: PMClient) {
        self.client = client
    }

    /// Fetches the full order book for a CLOB token.
    ///
    /// - Parameter tokenID: a token id from a market's ``PMMarket/clobTokenIds``.
    public func book(tokenID: String) async throws -> PMOrderbook {
        let url = try await client.clobURL(path: "/book", query: [
            URLQueryItem(name: "token_id", value: tokenID)
        ])
        let dto = try await client.get(BookDTO.self, url)
        return PMOrderbook(
            bids: dto.bids.map { PMLevel(price: $0.price.value, size: $0.size.value) },
            asks: dto.asks.map { PMLevel(price: $0.price.value, size: $0.size.value) }
        )
        // Note: ``PMOrderbook/decode(from:)`` performs the same mapping for the
        // offline (fixture) decode path used by tests.
    }

    /// Fetches the best price for a token on the given side.
    public func price(tokenID: String, side: PMSide) async throws -> Decimal {
        let url = try await client.clobURL(path: "/price", query: [
            URLQueryItem(name: "token_id", value: tokenID),
            URLQueryItem(name: "side", value: side.rawValue),
        ])
        return try await client.get(PriceDTO.self, url).price.value
    }

    /// Fetches the midpoint price between best bid and best ask for a token.
    public func midpoint(tokenID: String) async throws -> Decimal {
        let url = try await client.clobURL(path: "/midpoint", query: [
            URLQueryItem(name: "token_id", value: tokenID)
        ])
        return try await client.get(MidDTO.self, url).mid.value
    }
}
