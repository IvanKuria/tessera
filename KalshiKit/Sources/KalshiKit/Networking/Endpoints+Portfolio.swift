import Foundation

public extension KalshiClient {
    // MARK: - Balance

    /// Returns the authenticated account's balance. Path: `/portfolio/balance`.
    ///
    /// Requires a configured signer; throws ``KalshiError/notAuthenticated`` otherwise.
    func balance() async throws -> Balance {
        try await send(
            method: .get,
            path: "/portfolio/balance",
            authenticated: true
        )
    }

    // MARK: - Positions

    /// Lists the account's market/event positions. Path: `/portfolio/positions`.
    ///
    /// - Parameters:
    ///   - ticker: scope to a single market ticker.
    ///   - limit: page size.
    ///   - cursor: pagination cursor.
    func positions(
        ticker: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> PositionsResponse {
        var query: [URLQueryItem] = []
        if let ticker { query.append(URLQueryItem(name: "ticker", value: ticker)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/portfolio/positions",
            query: query,
            authenticated: true
        )
    }

    // MARK: - Orders

    /// Lists the account's orders. Path: `/portfolio/orders`.
    ///
    /// - Parameters:
    ///   - ticker: scope to a single market ticker.
    ///   - status: filter by order status (e.g. `"resting"`, `"canceled"`, `"executed"`).
    ///   - cursor: pagination cursor.
    func orders(
        ticker: String? = nil,
        status: String? = nil,
        cursor: String? = nil
    ) async throws -> OrdersResponse {
        var query: [URLQueryItem] = []
        if let ticker { query.append(URLQueryItem(name: "ticker", value: ticker)) }
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/portfolio/orders",
            query: query,
            authenticated: true
        )
    }

    // MARK: - Fills

    /// Lists the account's executed trades (fills). Path: `/portfolio/fills`.
    ///
    /// Requires a configured signer; throws ``KalshiError/notAuthenticated`` otherwise.
    ///
    /// - Parameters:
    ///   - ticker: scope to a single market ticker.
    ///   - limit: page size.
    ///   - cursor: pagination cursor.
    func fills(
        ticker: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> FillsResponse {
        var query: [URLQueryItem] = []
        if let ticker { query.append(URLQueryItem(name: "ticker", value: ticker)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/portfolio/fills",
            query: query,
            authenticated: true
        )
    }

    // MARK: - Settlements

    /// Lists the account's settled-market outcomes. Path: `/portfolio/settlements`.
    ///
    /// Requires a configured signer; throws ``KalshiError/notAuthenticated`` otherwise.
    ///
    /// - Parameters:
    ///   - limit: page size.
    ///   - cursor: pagination cursor.
    func settlements(
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> SettlementsResponse {
        var query: [URLQueryItem] = []
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

        return try await send(
            method: .get,
            path: "/portfolio/settlements",
            query: query,
            authenticated: true
        )
    }

    /// Places an order. `POST /portfolio/orders`. Unwraps ``OrderResponse``.
    ///
    /// The request is encoded with ``KalshiJSON/encoder`` (camelCase →
    /// `snake_case`).
    func createOrder(_ request: CreateOrderRequest) async throws -> Order {
        let body: Data
        do {
            body = try KalshiJSON.encoder.encode(request)
        } catch {
            throw KalshiError.decoding(underlying: error)
        }

        let response: OrderResponse = try await send(
            method: .post,
            path: "/portfolio/orders",
            body: body,
            authenticated: true
        )
        return response.order
    }

    /// Cancels a resting order by id. `DELETE /portfolio/orders/{orderId}`.
    ///
    /// Kalshi returns the (reduced) order on success; the response body is
    /// ignored here.
    func cancelOrder(orderId: String) async throws {
        // Decode into an empty placeholder; we ignore the body but still let the
        // transport surface non-2xx statuses as `KalshiError`.
        let _: EmptyResponse = try await send(
            method: .delete,
            path: "/portfolio/orders/\(orderId)",
            authenticated: true
        )
    }
}

/// A decode target for responses whose body we intentionally discard. Decodes
/// successfully from any JSON object (or absent body) so success statuses don't
/// trip the decoder.
struct EmptyResponse: Decodable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {}
}
