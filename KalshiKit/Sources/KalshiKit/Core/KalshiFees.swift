import Foundation

/// Kalshi trading-fee math.
///
/// Kalshi charges a per-trade fee that is **highest near a price of 50¢** and
/// smallest at the extremes — a detail the official UI does not surface, so a
/// client can win trust by previewing it. The published formula is
///
/// ```
/// fee = round_up( rate × C × P × (1 − P) )          // in dollars
/// ```
///
/// where `C` is the contract count and `P` is the price in dollars (`0…1`).
/// The result is rounded **up to the next whole cent**. `rate` is `0.07` for
/// liquidity-taking orders and `0.0175` for resting (maker) orders.
///
/// All math is done in `Decimal` (never `Double`) so the ceiling boundary —
/// e.g. an exact `1.75¢` — is computed precisely, consistent with
/// ``KalshiDecimal``.
public enum KalshiFees {

    /// Whether an order removes liquidity (taker) or rests on the book (maker).
    /// Taker is the conservative default for cost previews.
    public enum Role: Sendable {
        case taker
        case maker

        /// The fee rate applied to `C × P × (1 − P)`.
        var rate: Decimal {
            switch self {
            case .taker: return Decimal(7) / Decimal(100)       // 0.07
            case .maker: return Decimal(175) / Decimal(10_000)  // 0.0175
            }
        }
    }

    /// The trading fee, in **whole cents**, for `contracts` filled at
    /// `priceCents` (a per-contract price in `1…99`).
    ///
    /// Returns `0` when `contracts <= 0` or `priceCents` is outside `1…99`
    /// (no exposure ⇒ no fee). The result is the ceiling of the dollar fee
    /// expressed in cents, matching Kalshi's `round_up`.
    public static func tradingFeeCents(
        contracts: Int,
        priceCents: Int,
        role: Role = .taker
    ) -> Int {
        guard contracts > 0, (1...99).contains(priceCents) else { return 0 }

        // fee (dollars) = rate × C × (priceCents/100) × ((100 − priceCents)/100)
        // fee (cents)   = fee(dollars) × 100
        //               = rate × C × priceCents × (100 − priceCents) / 100
        let p = Decimal(priceCents)
        let complement = Decimal(100 - priceCents)
        let feeCents = role.rate * Decimal(contracts) * p * complement / Decimal(100)

        return ceilToInt(feeCents)
    }

    /// Rounds a non-negative `Decimal` up to the next integer (`round_up`).
    private static func ceilToInt(_ value: Decimal) -> Int {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .up) // .up = away from zero ⇒ ceiling for value ≥ 0
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
