import Foundation

/// Centralized price-conversion helpers.
///
/// The app previously re-implemented "dollar value → integer cents" in several
/// places. This single helper expresses that conversion once, using `Decimal`
/// math (via `NSDecimalNumber`) rather than `Double`, consistent with the rest
/// of the money handling in the SDK.
public extension KalshiDecimal {
    /// This dollar value expressed as an integer number of cents.
    ///
    /// Multiplies the underlying `Decimal` by 100 and rounds half-up to the
    /// nearest integer (e.g. `0.56` → `56`, `1.00` → `100`, `0.005` → `1`).
    /// Uses `NSDecimalNumber` rounding to avoid binary-floating-point error.
    var centsRounded: Int {
        let scaled = NSDecimalNumber(decimal: value * 100)
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return scaled.rounding(accordingToBehavior: handler).intValue
    }
}
