import Foundation

public enum ScannerMath {
    public static func ceilToCent(_ cents: Decimal) -> Decimal {
        var v = cents, out = Decimal()
        NSDecimalRound(&out, &v, 0, .up)
        return out
    }

    public static func feeRate(seriesTicker: String?, role: KalshiFees.Role, config: DetectorConfig) -> Decimal {
        if let s = seriesTicker, config.halfRateSeriesPrefixes.contains(where: { s.hasPrefix($0) }) {
            return Decimal(35) / Decimal(1000)
        }
        return role.rate
    }

    /// fee = ceil( rate * C * P * (100 - P) / 100 ) in whole cents.
    public static func feeCents(contracts: Decimal, priceCents: Int, rate: Decimal) -> Decimal {
        guard contracts > 0, (1...99).contains(priceCents) else { return 0 }
        let p = Decimal(priceCents)
        let raw = rate * contracts * p * (Decimal(100) - p) / Decimal(100)
        return ceilToCent(raw)
    }

    /// Greedily fill cheapest-first up to targetQty. Returns realized VWAP, filled qty, and total depth at-or-below the cutoff.
    public static func walk(ladder: [(price: Int, size: Decimal)], targetQty: Decimal)
        -> (vwapCents: Decimal, filled: Decimal, depthAvailable: Decimal) {
        let sorted = ladder.sorted { $0.price < $1.price }
        var remaining = targetQty, cost = Decimal(0), filled = Decimal(0), depth = Decimal(0)
        for level in sorted {
            depth += level.size
            if remaining > 0 {
                let take = min(remaining, level.size)
                cost += Decimal(level.price) * take
                filled += take
                remaining -= take
            }
        }
        let vwap = filled > 0 ? cost / filled : 0
        return (vwap, filled, depth)
    }

    public static func daysToSettlement(expiration: Date?, now: Date) -> Decimal {
        guard let expiration else { return Decimal(string: "0.5")! }
        let secs = expiration.timeIntervalSince(now)
        let days = secs / 86_400
        return max(Decimal(string: "0.5")!, Decimal(days))
    }

    public static func annualizedPct(netEdgePct: Decimal, days: Decimal) -> Decimal {
        guard days > 0 else { return 0 }
        return netEdgePct * Decimal(365) / days
    }
}
