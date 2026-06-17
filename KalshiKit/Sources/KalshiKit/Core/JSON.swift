import Foundation

/// Canonical JSON coders for the SDK. Every model and test decodes through
/// `KalshiJSON.decoder` so snake_case conversion is consistent everywhere.
public enum KalshiJSON {
    /// Decoder configured for Kalshi's wire format: `snake_case` keys map to
    /// camelCase properties automatically, so models use plain camelCase
    /// property names (add explicit `CodingKeys` only where conversion is
    /// ambiguous). Timestamps arrive as ISO-8601 strings or Unix ints depending
    /// on the field, so models decode those explicitly rather than via a global
    /// date strategy.
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Encoder mirroring the decoder, for request bodies (e.g. create order).
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
