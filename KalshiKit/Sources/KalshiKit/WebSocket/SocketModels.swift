import Foundation

/// Real-time channels on the Kalshi WebSocket feed.
///
/// Market-data channels (`orderbookDelta`, `ticker`, `trade`, `marketLifecycle`)
/// are public; user channels (`fill`, `marketPositions`, `userOrders`) require an
/// authenticated handshake. The raw values are the literal strings Kalshi expects.
public enum SocketChannel: String, Sendable, Hashable, CaseIterable {
    case orderbookDelta = "orderbook_delta"
    case ticker = "ticker"
    case trade = "trade"
    case marketLifecycle = "market_lifecycle_v2"
    case fill = "fill"
    case marketPositions = "market_positions"
    case userOrders = "user_orders"

    /// Whether subscribing to this channel requires a signed handshake.
    public var requiresAuth: Bool {
        switch self {
        case .fill, .marketPositions, .userOrders: return true
        case .orderbookDelta, .ticker, .trade, .marketLifecycle: return false
        }
    }
}

// MARK: - Outbound command

/// A `subscribe`/`unsubscribe` command sent to the server.
struct SocketCommand: Encodable {
    let id: Int
    let cmd: String
    let params: Params

    struct Params: Encodable {
        let channels: [String]
        let marketTickers: [String]?
    }
}

// MARK: - Inbound payloads (decoded via KalshiJSON.decoder → snake_case)

/// Lightweight probe to read the message `type` before decoding the full payload.
struct SocketProbe: Decodable {
    let type: String
    let id: Int?
    let sid: Int?
    let seq: Int?
}

/// Generic server envelope: `{ "type", "sid", "seq", "msg": { … } }`.
struct SocketEnvelope<Payload: Decodable>: Decodable {
    let type: String
    let sid: Int?
    let seq: Int?
    let msg: Payload?
}

/// Acknowledgement that a subscription is active.
public struct SocketSubscribed: Sendable, Decodable, Hashable {
    public var channel: String?
    public var sid: Int?
}

/// `ticker` channel update — best-bid/ask/last for a market. All optional and
/// tolerant: the feed mixes dollar-string and integer-cent encodings over time.
public struct TickerUpdate: Sendable, Decodable, Hashable {
    public var marketTicker: String?
    public var yesBid: Int?
    public var yesAsk: Int?
    public var price: Int?
    public var volume: Int?
    public var openInterest: Int?
    public var yesBidDollars: KalshiDecimal?
    public var yesAskDollars: KalshiDecimal?
    public var priceDollars: KalshiDecimal?
    public var ts: Int?

    public var date: Date? { KalshiTime.date(fromUnixSeconds: ts) }
}

/// `orderbook_delta` channel: full snapshot (first message) or incremental delta.
/// Snapshots populate `yes`/`no` level arrays; deltas carry a single price/level change.
public struct OrderbookUpdate: Sendable, Decodable, Hashable {
    public var marketTicker: String?
    /// Snapshot levels, each `[priceCents, restingContracts]`.
    public var yes: [[Int]]?
    public var no: [[Int]]?
    /// Delta fields.
    public var price: Int?
    public var delta: Int?
    public var side: OrderSide?
}

/// `trade` channel update — a public execution.
public struct TradeUpdate: Sendable, Decodable, Hashable {
    public var marketTicker: String?
    public var yesPrice: Int?
    public var noPrice: Int?
    public var yesPriceDollars: KalshiDecimal?
    public var noPriceDollars: KalshiDecimal?
    public var count: Int?
    public var countFp: KalshiDecimal?
    public var takerSide: OrderSide?
    public var ts: Int?

    public var date: Date? { KalshiTime.date(fromUnixSeconds: ts) }
}

// MARK: - Public event stream

/// One event delivered on `KalshiSocket.events`.
///
/// The stream is long-lived and does **not** terminate on transient errors:
/// disconnects surface as `.disconnected` and the client reconnects + resubscribes
/// automatically, surfacing `.connected` again. Consumers render `connectionState`
/// accordingly rather than treating the stream end as fatal.
public enum SocketEvent: Sendable {
    case connected
    case subscribed(SocketSubscribed)
    case ticker(TickerUpdate)
    case orderbook(OrderbookUpdate)
    case trade(TradeUpdate)
    case serverError(String)
    case disconnected(reason: String)
    /// A message whose `type` this SDK version does not model.
    case unknown(type: String)
}

/// Connection lifecycle state, suitable for a "Live / Reconnecting / Offline" badge.
public enum SocketConnectionState: Sendable, Hashable {
    case disconnected
    case connecting
    case connected
}
