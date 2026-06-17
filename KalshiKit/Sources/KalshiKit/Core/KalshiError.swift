import Foundation

/// Errors surfaced by the SDK.
public enum KalshiError: Error, Sendable {
    /// A URL or path could not be constructed.
    case invalidURL(String)
    /// The server returned a non-2xx status. `message` is Kalshi's `error` field when present.
    case http(status: Int, message: String?, body: Data?)
    /// HTTP 429. Kalshi sends no `Retry-After`; the client retries with its own backoff.
    case rateLimited
    /// Response body failed to decode into the expected model.
    case decoding(underlying: Error)
    /// Networking/transport failure (offline, TLS, timeout, …).
    case transport(underlying: Error)
    /// A call requiring authentication was made without configured credentials.
    case notAuthenticated
    /// RSA signing failed (bad key, import failure, etc.).
    case signing(reason: String)
    /// WebSocket protocol error.
    case webSocket(reason: String)
}

extension KalshiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .http(let status, let message, _):
            return "HTTP \(status)\(message.map { ": \($0)" } ?? "")"
        case .rateLimited: return "Rate limited (HTTP 429)."
        case .decoding(let e): return "Failed to decode response: \(e)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        case .notAuthenticated: return "This request requires Kalshi API credentials."
        case .signing(let reason): return "Request signing failed: \(reason)"
        case .webSocket(let reason): return "WebSocket error: \(reason)"
        }
    }
}
