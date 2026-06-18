import Foundation

/// Errors surfaced by the SDK.
public enum PMError: Error, Sendable {
    /// A URL or path could not be constructed.
    case invalidURL(String)
    /// The server returned a non-2xx status. `message` is the API's error text when present.
    case http(status: Int, message: String?, body: Data?)
    /// HTTP 429. Polymarket sends no `Retry-After`; the client retries with its own backoff.
    case rateLimited
    /// Response body failed to decode into the expected model.
    case decoding(underlying: Error)
    /// Networking/transport failure (offline, TLS, timeout, …).
    case transport(underlying: Error)
}

extension PMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .http(let status, let message, _):
            return "HTTP \(status)\(message.map { ": \($0)" } ?? "")"
        case .rateLimited: return "Rate limited (HTTP 429)."
        case .decoding(let e): return "Failed to decode response: \(e)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}
