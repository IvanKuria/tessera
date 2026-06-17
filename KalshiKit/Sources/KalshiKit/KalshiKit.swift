// KalshiKit
//
// An unofficial, open-source Swift SDK for the Kalshi trade API (v2).
// Not affiliated with, endorsed by, or connected to Kalshi / KalshiEX LLC.
//
// Covers keyless public market data, RSA-PSS authenticated trading, and the
// real-time WebSocket feed. See `KalshiEnvironment` for base URLs and
// `KalshiClient` for the entry point.

import Foundation

/// Library metadata.
public enum KalshiKit {
    /// Semantic version of the SDK.
    public static let version = "0.1.0"

    /// The `x-client`-style identifier sent with requests, useful for support/debugging.
    public static let userAgent = "KalshiKit/\(version) (Swift; macOS)"
}
