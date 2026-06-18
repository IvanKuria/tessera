import Foundation

/// Canonical JSON coders for the SDK.
public enum PMJSON {
    /// Decoder for Polymarket's wire format.
    ///
    /// **No** `convertFromSnakeCase` strategy: Gamma's market/event JSON is
    /// already camelCase (`conditionId`, `endDate`, `clobTokenIds`). The few
    /// CLOB fields that are snake_case (`asset_id`) are not decoded into models;
    /// where a snake_case field *is* needed it is mapped via explicit
    /// `CodingKeys`. Timestamps arrive as ISO-8601 strings and are decoded
    /// explicitly rather than via a global date strategy.
    public static let decoder = JSONDecoder()

    /// Encoder mirroring the decoder, for round-tripping models.
    public static let encoder = JSONEncoder()
}
