import Foundation

/// Selects which Kalshi backend the client talks to.
///
/// Base URLs are verified against docs.kalshi.com (June 2026). Note the TLD
/// difference: production is `.com`, the demo/sandbox is `.co`.
public enum KalshiEnvironment: Sendable, Equatable {
    /// Live production exchange. Real markets, real money.
    case production
    /// Demo / sandbox exchange. Use this for development and tests.
    case demo
    /// Escape hatch for a custom REST + WebSocket pair (e.g. a local proxy).
    case custom(rest: URL, webSocket: URL)

    /// REST base URL, including the `/trade-api/v2` path prefix.
    /// All endpoint paths in this SDK are appended to this.
    public var restBaseURL: URL {
        switch self {
        case .production:
            // `api.elections.kalshi.com` is the current public base and serves the
            // order book keyless (the `external-api` host 401s on the order book).
            return URL(string: "https://api.elections.kalshi.com/trade-api/v2")!
        case .demo:
            return URL(string: "https://demo-api.kalshi.co/trade-api/v2")!
        case .custom(let rest, _):
            return rest
        }
    }

    /// WebSocket URL for the real-time feed (`/trade-api/ws/v2`).
    public var webSocketURL: URL {
        switch self {
        case .production:
            return URL(string: "wss://api.elections.kalshi.com/trade-api/ws/v2")!
        case .demo:
            return URL(string: "wss://demo-api.kalshi.co/trade-api/ws/v2")!
        case .custom(_, let webSocket):
            return webSocket
        }
    }

    /// The path prefix every signed request must include in its signing string,
    /// e.g. `/trade-api/v2`. Derived from `restBaseURL`.
    public var signingPathPrefix: String {
        restBaseURL.path
    }
}
