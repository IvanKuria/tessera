import Foundation

/// A resting / historical order (read model, `GET /portfolio/orders`).
public struct Order: Codable, Sendable, Hashable, Identifiable {
    public var orderId: String
    public var ticker: String?
    /// Order status (e.g. `resting`, `canceled`, `executed`). Left as a raw
    /// string since the server's vocabulary here is broad and unstable.
    public var status: String?
    public var action: OrderAction?
    public var side: OrderSide?
    /// Limit price on the YES side, in cents.
    public var yesPrice: Int?
    /// Limit price on the NO side, in cents.
    public var noPrice: Int?
    public var count: Int?
    public var remainingCount: Int?
    /// Raw ISO-8601 creation time (see `createdDate`).
    public var createdTime: String?
    /// Caller-supplied idempotency id echoed back by the server.
    public var clientOrderId: String?

    /// Natural identity is the server order id.
    public var id: String { orderId }

    /// Parsed creation time.
    public var createdDate: Date? { KalshiTime.date(fromISO: createdTime) }

    public init(
        orderId: String,
        ticker: String? = nil,
        status: String? = nil,
        action: OrderAction? = nil,
        side: OrderSide? = nil,
        yesPrice: Int? = nil,
        noPrice: Int? = nil,
        count: Int? = nil,
        remainingCount: Int? = nil,
        createdTime: String? = nil,
        clientOrderId: String? = nil
    ) {
        self.orderId = orderId
        self.ticker = ticker
        self.status = status
        self.action = action
        self.side = side
        self.yesPrice = yesPrice
        self.noPrice = noPrice
        self.count = count
        self.remainingCount = remainingCount
        self.createdTime = createdTime
        self.clientOrderId = clientOrderId
    }
}

/// Paged list of orders (`GET /portfolio/orders`).
public struct OrdersResponse: Codable, Sendable, Hashable, CursorPaged {
    public var orders: [Order]
    public var cursor: String?

    /// `CursorPaged` items projection.
    public var items: [Order] { orders }

    public init(orders: [Order], cursor: String? = nil) {
        self.orders = orders
        self.cursor = cursor
    }
}

/// Single-order endpoint envelope (e.g. response to create/cancel order).
public struct OrderResponse: Codable, Sendable, Hashable {
    public var order: Order

    public init(order: Order) {
        self.order = order
    }
}

// MARK: - Create order request

/// Request body for placing an order (`POST /portfolio/orders`).
///
/// Encoded via `KalshiJSON.encoder` (snake_case). Enum raw values are the
/// literal API strings, which `convertToSnakeCase` leaves untouched.
public struct CreateOrderRequest: Codable, Sendable, Hashable {
    public var ticker: String
    public var action: OrderAction
    public var side: OrderSide
    public var count: Int
    /// `"limit"` or `"market"`.
    public var type: String?
    /// Limit price on the YES side, in cents.
    public var yesPrice: Int?
    /// Limit price on the NO side, in cents.
    public var noPrice: Int?
    public var timeInForce: TimeInForce?
    /// Caller-supplied idempotency id (recommended to be a fresh UUID string).
    public var clientOrderId: String
    /// Max cost (in cents) the caller will pay; useful for market buys.
    public var buyMaxCost: Int?

    public init(
        ticker: String,
        action: OrderAction,
        side: OrderSide,
        count: Int,
        type: String? = "limit",
        yesPrice: Int? = nil,
        noPrice: Int? = nil,
        timeInForce: TimeInForce? = nil,
        clientOrderId: String,
        buyMaxCost: Int? = nil
    ) {
        self.ticker = ticker
        self.action = action
        self.side = side
        self.count = count
        self.type = type
        self.yesPrice = yesPrice
        self.noPrice = noPrice
        self.timeInForce = timeInForce
        self.clientOrderId = clientOrderId
        self.buyMaxCost = buyMaxCost
    }
}
