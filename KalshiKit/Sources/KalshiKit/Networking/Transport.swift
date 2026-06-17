import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP method used by the transport layer.
enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
}

extension KalshiClient {
    /// Internal sentinel thrown by ``decode(_:from:response:)`` on HTTP 429 so the
    /// retry loop in ``send(_:method:path:query:body:authenticated:)`` can catch and
    /// retry it. Never escapes the client: it is converted to `.rateLimited` once
    /// retries are exhausted.
    struct RateLimitSentinel: Error {}

    /// Builds a `URLRequest` for the given relative path and query items.
    ///
    /// The relative `path` (e.g. `"/markets"`) is appended to
    /// `environment.restBaseURL` **without** dropping the base's `/trade-api/v2`
    /// prefix. We start from `restBaseURL` via `URLComponents` and append to its
    /// `path` rather than using `URL(string:relativeTo:)`, which would discard the
    /// base path.
    ///
    /// - Returns: the request, plus the full signing path (including
    ///   `/trade-api/v2`, excluding the query string) for use by the signer.
    func makeRequest(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        body: Data?
    ) throws -> (request: URLRequest, signingPath: String) {
        let base = environment.restBaseURL
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw KalshiError.invalidURL(base.absoluteString)
        }

        // Append the relative path to the base path, normalizing any duplicate slashes.
        let basePath = components.path
        let relative = path.hasPrefix("/") ? path : "/" + path
        let fullPath = (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath) + relative
        components.path = fullPath

        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw KalshiError.invalidURL(base.absoluteString + path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(KalshiKit.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // `fullPath` is exactly the signing path: includes `/trade-api/v2`, excludes query.
        return (request, fullPath)
    }

    /// Core request pipeline: build, (optionally) sign, execute, retry, decode.
    ///
    /// - Parameters:
    ///   - method: HTTP method.
    ///   - path: relative path (e.g. `"/markets"`); resolved against the env base URL.
    ///   - query: query items (omit `nil`-valued ones before calling).
    ///   - body: encoded JSON body, if any.
    ///   - authenticated: when `true`, signing headers are required (else `.notAuthenticated`);
    ///     when `false`, signing headers are added only if a signer is present.
    func send<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await performOnce(
                    type,
                    method: method,
                    path: path,
                    query: query,
                    body: body,
                    authenticated: authenticated
                )
            } catch is RateLimitSentinel {
                guard attempt < backoff.maxRetries else { throw KalshiError.rateLimited }
                let seconds = backoff.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                attempt += 1
            }
        }
    }

    /// A single build → sign → execute → decode pass (no retries).
    private func performOnce<T: Decodable & Sendable>(
        _ type: T.Type,
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        authenticated: Bool
    ) async throws -> T {
        let (baseRequest, signingPath) = try makeRequest(
            method: method,
            path: path,
            query: query,
            body: body
        )
        var request = baseRequest

        // Authentication headers.
        if authenticated || signer != nil {
            guard let signer else {
                // Only reachable when `authenticated == true` and no signer is set.
                throw KalshiError.notAuthenticated
            }
            let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
            do {
                let headers = try signer.authHeaders(
                    method: method.rawValue,
                    path: signingPath,
                    timestampMs: timestampMs
                )
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            } catch let error as KalshiError {
                throw error
            } catch {
                throw KalshiError.signing(reason: String(describing: error))
            }
        }

        // Execute.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw KalshiError.transport(underlying: error)
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
            throw KalshiError.transport(underlying: URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299:
            // Tolerate empty bodies (e.g. 204 No Content) for void-style calls.
            if data.isEmpty, let empty = EmptyResponse() as? T {
                return empty
            }
            do {
                return try KalshiJSON.decoder.decode(T.self, from: data)
            } catch {
                throw KalshiError.decoding(underlying: error)
            }
        case 429:
            // Signal the retry loop; converted to `.rateLimited` if retries run out.
            throw RateLimitSentinel()
        default:
            let message = Self.errorMessage(from: data)
            throw KalshiError.http(status: http.statusCode, message: message, body: data)
        }
    }

    /// Best-effort extraction of an error message from a Kalshi error body.
    ///
    /// Handles both `{"error": "..."}` and `{"error": {"message": "..."}}`
    /// shapes, plus a top-level `{"message": "..."}` fallback.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? String {
            return error
        }
        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let detail = error["detail"] as? String { return detail }
        }
        if let message = object["message"] as? String {
            return message
        }
        return nil
    }
}
