import Foundation
import KalshiKit

/// Per-venue trading-fee math, in whole cents.
///
/// Kalshi charges its quadratic taker fee (highest near 50¢); Polymarket trades
/// are generally fee-free, so its leg contributes nothing.
public enum VenueFees {
    /// The fee in whole cents for filling `contracts` at `priceCents` on `venue`.
    public static func feeCents(venue: Venue, contracts: Decimal, priceCents: Int) -> Decimal {
        switch venue {
        case .kalshi:
            return ScannerMath.feeCents(
                contracts: contracts,
                priceCents: priceCents,
                rate: KalshiFees.Role.taker.rate
            )
        case .polymarket:
            return 0
        }
    }
}
