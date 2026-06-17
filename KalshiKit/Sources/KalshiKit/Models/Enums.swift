import Foundation

// MARK: - Shared date formatter

/// Shared helpers for decoding Kalshi's two time encodings.
///
/// Kalshi expresses timestamps two ways:
///  - ISO-8601 strings (`open_time`, `close_time`, `created_time`, …), parsed
///    with a fractional-seconds-aware formatter.
///  - Unix epoch **seconds** integers (`settlement_ts`, `updated_ts`,
///    `end_period_ts`, …).
///
/// Both are stored raw on the models and exposed as computed `Date?` accessors
/// so the SDK never loses information on a parse miss.
enum KalshiTime {
    /// ISO-8601 parser tolerant of fractional seconds (`2026-01-02T15:04:05.123Z`).
    ///
    /// Configured once and never mutated; `ISO8601DateFormatter` is not marked
    /// `Sendable` but is safe for concurrent reads of `date(from:)`, hence
    /// `nonisolated(unsafe)`.
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback parser for timestamps without fractional seconds.
    nonisolated(unsafe) static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses an ISO-8601 string, tolerating presence/absence of fractional seconds.
    static func date(fromISO string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = iso8601.date(from: string) { return d }
        return iso8601NoFraction.date(from: string)
    }

    /// Converts a Unix epoch **seconds** value to a `Date`.
    static func date(fromUnixSeconds ts: Int?) -> Date? {
        guard let ts else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }
}

// MARK: - Server string enums (with `unknown` fallback)

/// Lifecycle state of a market.
///
/// Values verified against live production JSON (June 2026): an open, tradeable
/// market reports `"active"`. Note this differs from the `status` **filter**
/// query param, which accepts `"open"`. `isOpen` papers over both.
public enum MarketStatus: String, Codable, Sendable, Hashable {
    case unopened
    case active
    case paused
    case closed
    case determined
    case settled
    case finalized
    /// Any value the server returns that this SDK version does not recognize.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MarketStatus(rawValue: raw) ?? .unknown
    }

    /// True when the market is currently open for trading.
    public var isOpen: Bool { self == .active }
}

/// Settled outcome of a market. The wire field is optional and may be `""`.
public enum MarketResult: String, Codable, Sendable, Hashable {
    case yes
    case no
    case void
    /// Any value the server returns that this SDK version does not recognize.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MarketResult(rawValue: raw) ?? .unknown
    }
}

/// The side of a contract: `yes` or `no`.
public enum OrderSide: String, Codable, Sendable, Hashable {
    case yes
    case no
    /// Any value the server returns that this SDK version does not recognize.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrderSide(rawValue: raw) ?? .unknown
    }
}

/// Whether an order buys or sells contracts.
public enum OrderAction: String, Codable, Sendable, Hashable {
    case buy
    case sell
    /// Any value the server returns that this SDK version does not recognize.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrderAction(rawValue: raw) ?? .unknown
    }
}

/// How long an order remains active.
///
/// `convertFromSnakeCase` only transforms **keys**, not string **values**, so
/// the raw values below are the literal API strings.
public enum TimeInForce: String, Codable, Sendable, Hashable {
    case fillOrKill = "fill_or_kill"
    case goodTillCanceled = "good_till_canceled"
    case immediateOrCancel = "immediate_or_cancel"
    /// Any value the server returns that this SDK version does not recognize.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TimeInForce(rawValue: raw) ?? .unknown
    }
}
