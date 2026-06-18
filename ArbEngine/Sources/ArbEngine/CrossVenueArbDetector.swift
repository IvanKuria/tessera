import Foundation
import KalshiKit

/// Detects a guaranteed cross-venue lock between a matched Kalshi ⇆ Polymarket
/// binary pair: buy YES on one venue and NO on the other so the two legs cover
/// both outcomes for less than the 100¢ guaranteed payout.
///
/// Both orientations are tried — (YES Kalshi + NO Polymarket) and
/// (YES Polymarket + NO Kalshi) — each depth-walked to the target size with
/// per-venue fees applied; the better net-positive orientation wins. Returns
/// `nil` when neither orientation clears the min-net-edge hurdle.
public enum CrossVenueArbDetector {

    /// Comfort threshold: below this match confidence the opportunity carries a
    /// `.lowMatchConfidence` warning (it is still surfaced, just flagged).
    static let comfortConfidence = Decimal(string: "0.75")!

    public static func detect(
        _ pair: MatchedPair,
        books: VenueBooks,
        config: DetectorConfig,
        now: Date
    ) -> Opportunity? {
        let candidates = [
            evaluate(
                pair: pair,
                yesVenue: .kalshi, yesLadder: books.kalshiYesAsk, yesTicker: pair.kalshi.id,
                noVenue: .polymarket, noLadder: books.pmNoAsk, noTicker: pair.polymarket.id,
                config: config, now: now
            ),
            evaluate(
                pair: pair,
                yesVenue: .polymarket, yesLadder: books.pmYesAsk, yesTicker: pair.polymarket.id,
                noVenue: .kalshi, noLadder: books.kalshiNoAsk, noTicker: pair.kalshi.id,
                config: config, now: now
            ),
        ].compactMap { $0 }

        // Pick the richer net edge.
        return candidates.max { $0.netEdgeCents < $1.netEdgeCents }
    }

    // MARK: One orientation

    private static func evaluate(
        pair: MatchedPair,
        yesVenue: Venue, yesLadder: [Ladder.Level], yesTicker: String,
        noVenue: Venue, noLadder: [Ladder.Level], noTicker: String,
        config: DetectorConfig, now: Date
    ) -> Opportunity? {
        guard !yesLadder.isEmpty, !noLadder.isEmpty else { return nil }

        // Best-ask lock gate: cheapest YES + cheapest NO must clear < 100¢.
        let bestYes = yesLadder.map(\.price).min() ?? 100
        let bestNo = noLadder.map(\.price).min() ?? 100
        guard bestYes + bestNo < 100 else { return nil }

        let q = Decimal(config.maxStakeContracts)
        let wYes = ScannerMath.walk(ladder: yesLadder, targetQty: q)
        let wNo = ScannerMath.walk(ladder: noLadder, targetQty: q)
        // Fill only what both sides can support (a lock needs both legs).
        let filled = min(wYes.filled, wNo.filled)
        guard filled > 0 else { return nil }
        let minDepth = min(wYes.depthAvailable, wNo.depthAvailable)

        let yesPriceC = NSDecimalNumber(decimal: ScannerMath.ceilToCent(wYes.vwapCents)).intValue
        let noPriceC = NSDecimalNumber(decimal: ScannerMath.ceilToCent(wNo.vwapCents)).intValue

        let feeYes = VenueFees.feeCents(venue: yesVenue, contracts: filled, priceCents: yesPriceC)
        let feeNo = VenueFees.feeCents(venue: noVenue, contracts: filled, priceCents: noPriceC)
        let totalFees = feeYes + feeNo

        let vwapSum = wYes.vwapCents + wNo.vwapCents
        let grossPerSet = Decimal(100) - vwapSum
        let grossAtQ = grossPerSet * filled
        let netAtQ = grossAtQ - totalFees
        guard netAtQ > 0 else { return nil }

        let netPerContract = grossPerSet - (totalFees / filled)
        guard netPerContract >= config.minNetEdgeCents else { return nil }

        let outlay = vwapSum * filled + totalFees
        let netPct = outlay > 0 ? netAtQ / outlay : 0

        let exp = [pair.kalshi.closeDate, pair.polymarket.closeDate].compactMap { $0 }.max()
        let days = ScannerMath.daysToSettlement(expiration: exp, now: now)
        let annual = ScannerMath.annualizedPct(netEdgePct: netPct, days: days)

        let legs = [
            Leg(marketTicker: yesTicker, side: .yes, priceCents: yesPriceC, qty: filled,
                feeCents: feeYes, depthAvailable: wYes.depthAvailable, vwapCents: wYes.vwapCents, venue: yesVenue),
            Leg(marketTicker: noTicker, side: .no, priceCents: noPriceC, qty: filled,
                feeCents: feeNo, depthAvailable: wNo.depthAvailable, vwapCents: wNo.vwapCents, venue: noVenue),
        ]

        // Cross-venue settlement risk is intrinsic; always flag.
        var warnings: [ScannerWarning] = [.crossVenueSettlement]
        if pair.resolutionMismatch { warnings.append(.resolutionMismatch) }
        if pair.confidence < comfortConfidence {
            warnings.append(.lowMatchConfidence(score: pair.confidence))
        }
        if minDepth < Decimal(5) { warnings.append(.oneContractMirage(maxQty: minDepth)) }
        if annual < config.hurdleAPR * 100 {
            warnings.append(.belowHurdle(annualizedPct: annual, hurdlePct: config.hurdleAPR * 100))
        }

        let kind: OpportunityKind = .edge(.crossVenueArb)
        return Opportunity(
            id: Opportunity.makeID(kind: kind, legs: legs),
            kind: kind,
            eventTicker: pair.kalshi.id,
            seriesTicker: nil,
            title: pair.kalshi.title,
            category: pair.kalshi.category ?? pair.polymarket.category,
            legs: legs,
            grossEdgeCents: grossAtQ,
            totalFeesCents: totalFees,
            netEdgeCents: netAtQ,
            netEdgePerContractCents: netPerContract,
            netEdgePct: netPct,
            maxContractsAtPositiveEdge: minDepth,
            capitalRequiredCents: outlay,
            maxLossIfLeggedOutCents: outlay,
            daysToSettlement: days,
            annualizedPct: annual,
            freshnessTimestamp: now,
            freshnessAgeSeconds: 0,
            confidence: pair.confidence,
            leggingRisk: .high,  // independent venues, no atomic fill
            warnings: warnings,
            isLive: false
        )
    }
}
