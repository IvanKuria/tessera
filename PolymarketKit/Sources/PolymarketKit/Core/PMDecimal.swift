import Foundation

/// A money/probability value that decodes from Polymarket's **string** form
/// (e.g. `"0.52"`, `"828622.70"`) while tolerating a raw JSON number.
///
/// Polymarket expresses prices, volumes and sizes as decimal strings on the
/// wire (`"outcomePrices"`, `"volume"`, order-book `"price"`/`"size"`). These
/// are money/probabilities: they are stored as `Decimal`, never `Double`, to
/// avoid binary-floating-point rounding error.
public struct PMDecimal: Sendable, Hashable, Comparable, Codable {
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
            guard let parsed = PMDecimal(string: s) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not a valid decimal string: \(s)"
                )
            }
            self = parsed
        } else {
            // Fall back to a numeric JSON value (Gamma also exposes `volumeNum`).
            self.value = try container.decode(Decimal.self)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // Encode back as a string to round-trip with Polymarket's wire format.
        var container = encoder.singleValueContainer()
        try container.encode("\(value)")
    }

    public static func < (lhs: PMDecimal, rhs: PMDecimal) -> Bool {
        lhs.value < rhs.value
    }
}

public extension PMDecimal {
    /// `Double` projection for charts/UI only — never for money math.
    var doubleValue: Double { NSDecimalNumber(decimal: value).doubleValue }

    /// The value expressed in **cents**, rounded half-up to the nearest integer.
    ///
    /// Polymarket prices live in `0...1`, so `×100` yields cents: `0.52 → 52`,
    /// `0.525 → 53` (half rounds up), `0.005 → 1`. Rounding uses
    /// `NSDecimalNumber` decimal rounding (`.plain`, scale 0) to stay exact.
    var centsRounded: Int {
        let cents = value * 100
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: cents).rounding(accordingToBehavior: handler).intValue
    }
}
