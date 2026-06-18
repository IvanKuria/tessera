// PolymarketKit
//
// An unofficial, open-source Swift SDK for Polymarket's public market-data
// APIs (the Gamma metadata API and the CLOB order-book API).
//
// Not affiliated with, endorsed by, or connected to Polymarket.
//
// Covers keyless public market data only. See `PMEnvironment` for the base
// URLs and `PMClient` for the entry point.

import Foundation

/// Library metadata.
public enum PolymarketKit {
    /// Semantic version of the SDK.
    public static let version = "1.0.0"

    /// User-Agent sent with every request. Polymarket's Gamma API rejects
    /// requests with a blank `User-Agent`, so `PMClient` always sets this.
    public static let userAgent = "PolymarketKit/\(version)"
}

/// Base URLs for Polymarket's public APIs.
///
/// Polymarket exposes two independent keyless services: the **Gamma** API for
/// market/event metadata, and the **CLOB** API for live order books and
/// prices. They have distinct hosts, so they are modeled as separate base URLs
/// rather than one environment.
public enum PMEnvironment {
    /// Gamma metadata API base, e.g. `…/markets`, `…/events`.
    public static let gammaBaseURL = URL(string: "https://gamma-api.polymarket.com")!

    /// CLOB order-book API base, e.g. `…/book`, `…/price`, `…/midpoint`.
    public static let clobBaseURL = URL(string: "https://clob.polymarket.com")!
}
