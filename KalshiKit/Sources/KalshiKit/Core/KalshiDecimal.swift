import Foundation

/// A money/quantity value that decodes from Kalshi's fixed-point **string** form
/// (e.g. `"0.5600"`, `"1234.00"`) while tolerating a raw JSON number.
///
/// Kalshi's 2026 read model expresses prices and sizes as dollar/fixed-point
/// strings (`yes_bid_dollars`, `volume_fp`, …). These are money: they are stored
/// as `Decimal`, never `Double`, to avoid binary-floating-point rounding error.
public struct KalshiDecimal: Sendable, Hashable, Comparable, Codable {
    public var value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init?(string: String) {
        // `Decimal(string:)` is locale-sensitive for separators; the API always
        // uses `.` so parse with the POSIX locale for determinism.
        guard let d = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self.value = d
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            guard let parsed = KalshiDecimal(string: s) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not a valid decimal string: \(s)"
                )
            }
            self = parsed
        } else {
            // Fall back to a numeric JSON value (legacy/uncommon).
            self.value = try container.decode(Decimal.self)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // Encode back as a string to round-trip with Kalshi's wire format.
        var container = encoder.singleValueContainer()
        try container.encode("\(value)")
    }

    public static func < (lhs: KalshiDecimal, rhs: KalshiDecimal) -> Bool {
        lhs.value < rhs.value
    }
}

public extension KalshiDecimal {
    /// `Double` projection for charts/UI only — never for money math.
    var doubleValue: Double { NSDecimalNumber(decimal: value).doubleValue }
}
