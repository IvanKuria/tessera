import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The main entry point to the Kalshi trade API (v2).
///
/// `KalshiClient` is an `actor`: it serializes access to its mutable state (the
/// optional request signer) so it is safe to share across tasks under Swift 6
/// strict concurrency. Keyless market-data calls work without credentials;
/// portfolio/trading calls require a configured ``RequestSigning`` signer.
///
/// ```swift
/// let client = KalshiClient(environment: .demo)
/// let markets = try await client.markets(status: "open")
///
/// await client.setSigner(mySigner)
/// let balance = try await client.balance()
/// ```
public actor KalshiClient {
    /// The selected backend (base URLs, signing prefix).
    let environment: KalshiEnvironment
    /// The URL session used for all requests. `URLSession` is `Sendable`.
    let urlSession: URLSession
    /// Retry/backoff policy applied to 429 responses.
    let backoff: Backoff
    /// The request signer, or `nil` when only keyless calls are available.
    private(set) var signer: (any RequestSigning)?

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - environment: which Kalshi backend to talk to. Defaults to `.production`.
    ///   - signer: an optional request signer enabling authenticated endpoints.
    ///   - urlSession: the URL session to execute requests on. Defaults to `.shared`.
    public init(
        environment: KalshiEnvironment = .production,
        signer: (any RequestSigning)? = nil,
        urlSession: URLSession = .shared
    ) {
        self.environment = environment
        self.signer = signer
        self.urlSession = urlSession
        self.backoff = .default
    }

    /// Internal designated initializer allowing a custom backoff policy (tests).
    init(
        environment: KalshiEnvironment,
        signer: (any RequestSigning)?,
        urlSession: URLSession,
        backoff: Backoff
    ) {
        self.environment = environment
        self.signer = signer
        self.urlSession = urlSession
        self.backoff = backoff
    }

    /// `true` when a signer is configured and authenticated endpoints are usable.
    public var isAuthenticated: Bool { signer != nil }

    /// Installs or removes the request signer at runtime.
    ///
    /// Pass `nil` to drop credentials (e.g. on sign-out); subsequent
    /// authenticated calls will then throw ``KalshiError/notAuthenticated``.
    public func setSigner(_ signer: (any RequestSigning)?) {
        self.signer = signer
    }

    // MARK: - Pagination

    /// Maximum number of pages ``collect(_:)`` will fetch before giving up, a
    /// safety valve against an endpoint that never returns an empty cursor.
    static let maxPaginationPages = 100

    /// Walks a cursor-paginated endpoint to completion, accumulating every item.
    ///
    /// `fetch` is invoked with `nil` for the first page and the previous page's
    /// ``CursorPaged/nextCursor`` thereafter, stopping when the cursor is exhausted
    /// or ``maxPaginationPages`` is reached.
    ///
    /// - Parameter fetch: fetches one page given an optional cursor.
    /// - Returns: every element across all pages, in order.
    public func collect<Page: CursorPaged & Decodable & Sendable>(
        _ fetch: @Sendable (_ cursor: String?) async throws -> Page
    ) async throws -> [Page.Element] {
        var results: [Page.Element] = []
        var cursor: String? = nil
        var pages = 0

        repeat {
            let page = try await fetch(cursor)
            results.append(contentsOf: page.items)
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil && pages < Self.maxPaginationPages

        return results
    }

    /// Convenience: every open market, optionally scoped to one series, paginated
    /// to completion via ``collect(_:)``.
    public func allOpenMarkets(seriesTicker: String? = nil) async throws -> [Market] {
        try await collect { [self] cursor in
            try await markets(
                status: "open",
                seriesTicker: seriesTicker,
                limit: 1000,
                cursor: cursor
            )
        }
    }
}
