import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The shared transport for Polymarket's keyless public APIs.
///
/// `PMClient` is an `actor`: it serializes access to its (immutable) state so it
/// is safe to share across tasks under Swift 6 strict concurrency. It builds
/// requests, **always** sets the `User-Agent` (Gamma rejects blank ones),
/// retries 429/5xx responses with jittered backoff, and decodes via
/// ``PMJSON/decoder``.
///
/// ```swift
/// let client = PMClient()
/// let gamma = GammaService(client: client)
/// let markets = try await gamma.markets(closed: false, limit: 20)
/// ```
public actor PMClient {
    /// The URL session used for all requests. `URLSession` is `Sendable`.
    let urlSession: URLSession
    /// Retry/backoff policy applied to 429 and 5xx responses.
    let backoff: Backoff

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - urlSession: the URL session to execute requests on. Defaults to `.shared`.
    ///   - backoff: the retry policy. Defaults to ``Backoff/default``.
    public init(urlSession: URLSession = .shared, backoff: Backoff = .default) {
        self.urlSession = urlSession
        self.backoff = backoff
    }

    // MARK: - URL building

    /// Builds an absolute URL by appending `path` and `query` to a base host.
    func makeURL(base: URL, path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw PMError.invalidURL(base.absoluteString)
        }
        let basePath = components.path
        let relative = path.hasPrefix("/") ? path : "/" + path
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        components.path = trimmedBase + relative
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw PMError.invalidURL(base.absoluteString + path)
        }
        return url
    }

    /// Builds a Gamma API URL (`https://gamma-api.polymarket.com/...`).
    func gammaURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        try makeURL(base: PMEnvironment.gammaBaseURL, path: path, query: query)
    }

    /// Builds a CLOB API URL (`https://clob.polymarket.com/...`).
    func clobURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        try makeURL(base: PMEnvironment.clobBaseURL, path: path, query: query)
    }

    // MARK: - GET

    /// Internal sentinel thrown by ``decode(_:from:response:)`` on retryable
    /// statuses (429, 5xx) so the retry loop in ``get(_:_:)`` can catch and
    /// retry. Never escapes the client: it is converted to ``PMError`` once
    /// retries are exhausted.
    private struct RetrySentinel: Error {
        let status: Int
        let body: Data
    }

    /// Performs a `GET` against an absolute URL, retrying 429/5xx with backoff,
    /// and decodes the 2xx body into `T`.
    public func get<T: Decodable & Sendable>(_ type: T.Type = T.self, _ url: URL) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await performOnce(type, url: url)
            } catch let sentinel as RetrySentinel {
                guard attempt < backoff.maxRetries else {
                    if sentinel.status == 429 { throw PMError.rateLimited }
                    let message = Self.errorMessage(from: sentinel.body)
                    throw PMError.http(status: sentinel.status, message: message, body: sentinel.body)
                }
                let seconds = backoff.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                attempt += 1
            }
        }
    }

    /// A single build → execute → decode pass (no retries).
    private func performOnce<T: Decodable & Sendable>(_ type: T.Type, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // ALWAYS set the User-Agent: Gamma rejects requests with a blank one.
        request.setValue(PolymarketKit.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw PMError.transport(underlying: error)
        }
        return try decode(type, from: data, response: response)
    }

    /// Inspects the HTTP status and decodes (or throws) accordingly.
    private func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data,
        response: URLResponse
    ) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw PMError.transport(underlying: URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299:
            do {
                return try PMJSON.decoder.decode(T.self, from: data)
            } catch {
                throw PMError.decoding(underlying: error)
            }
        case 429, 500...599:
            // Signal the retry loop; converted to a `PMError` if retries run out.
            throw RetrySentinel(status: http.statusCode, body: data)
        default:
            let message = Self.errorMessage(from: data)
            throw PMError.http(status: http.statusCode, message: message, body: data)
        }
    }

    /// Best-effort extraction of an error message from a Polymarket error body.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? String { return error }
        if let message = object["message"] as? String { return message }
        return nil
    }
}
