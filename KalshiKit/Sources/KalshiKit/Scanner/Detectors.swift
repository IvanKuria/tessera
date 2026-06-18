import Foundation

public protocol Detector: Sendable {
    static var detectorID: String { get }
    static func scan(_ snapshot: ScanSnapshot) -> [Opportunity]
}

public enum MultiOutcomeLockDetector: Detector {
    public static let detectorID = "multiOutcomeLock"

    public static func scan(_ snapshot: ScanSnapshot) -> [Opportunity] {
        var out: [Opportunity] = []
        for event in snapshot.events where event.mutuallyExclusive {
            let active = event.markets
            guard active.count >= 2 else { continue }
            if let o = underround(event, active, snapshot) { out.append(o) }
            if let o = overround(event, active, snapshot) { out.append(o) }
        }
        return out
    }

    // Buy YES on all: profitable iff Σ bestYesAsk < 100.
    private static func underround(_ e: EventSnapshot, _ markets: [MarketSnapshot], _ snap: ScanSnapshot) -> Opportunity? {
        let asks = markets.map { $0.bestYesAskCents }
        guard !asks.contains(nil) else { return nil }
        let yesSum = asks.compactMap { $0 }.reduce(0, +)
        guard yesSum < 100 else { return nil }
        return price(kind: .lock(.multiOutcomeUnderround), event: e, markets: markets, side: .yes,
                     ladderFor: { $0.yesAskLadder }, perSetGuaranteedPayout: 100, yesSumCents: Decimal(yesSum), snap: snap)
    }

    // Buy NO on all: profitable iff Σ bestYesBid > 100 (overround). payout = 100*(N-1).
    private static func overround(_ e: EventSnapshot, _ markets: [MarketSnapshot], _ snap: ScanSnapshot) -> Opportunity? {
        let bids = markets.map { $0.bestYesBidCents }
        guard !bids.contains(nil) else { return nil }
        let yesBidSum = bids.compactMap { $0 }.reduce(0, +)
        guard yesBidSum > 100 else { return nil }
        let payout = 100 * (markets.count - 1)
        return price(kind: .lock(.multiOutcomeOverround), event: e, markets: markets, side: .no,
                     ladderFor: { $0.noAskLadder }, perSetGuaranteedPayout: payout, yesSumCents: Decimal(yesBidSum), snap: snap)
    }

    private static func price(kind: OpportunityKind, event: EventSnapshot, markets: [MarketSnapshot], side: Side,
                              ladderFor: (MarketSnapshot) -> [(price: Int, size: Decimal)],
                              perSetGuaranteedPayout: Int, yesSumCents: Decimal, snap: ScanSnapshot) -> Opportunity? {
        let cfg = snap.config
        let targetQ = Decimal(cfg.maxStakeContracts)
        // Per-leg VWAP walk at target size; depth = min across legs.
        var legs: [Leg] = []
        var vwapSum = Decimal(0)
        var minDepth = Decimal.greatestFiniteMagnitude
        for m in markets {
            let ladder = ladderFor(m)
            guard !ladder.isEmpty else { return nil }
            let w = ScannerMath.walk(ladder: ladder, targetQty: targetQ)
            minDepth = min(minDepth, w.depthAvailable)
            vwapSum += w.vwapCents
            let priceC = (side == .yes ? m.bestYesAskCents : m.bestNoAskCents) ?? NSDecimalNumber(decimal: ScannerMath.ceilToCent(w.vwapCents)).intValue
            let rate = ScannerMath.feeRate(seriesTicker: m.seriesTicker, role: cfg.feeRole, config: cfg)
            let fee = ScannerMath.feeCents(contracts: targetQ, priceCents: priceC, rate: rate)
            legs.append(Leg(marketTicker: m.ticker, side: side, priceCents: priceC, qty: targetQ,
                            feeCents: fee, depthAvailable: w.depthAvailable, vwapCents: w.vwapCents))
        }
        let totalFees = legs.map(\.feeCents).reduce(0, +)
        // gross per set: underround = 100 - Σvwap ; overround = payout - Σvwap
        let grossPerSet = Decimal(perSetGuaranteedPayout) - vwapSum
        let grossAtQ = grossPerSet * targetQ
        let netAtQ = grossAtQ - totalFees
        guard netAtQ > 0 else { return nil }            // fee-killed → drop
        let netPerContract = grossPerSet - (totalFees / targetQ)
        guard netPerContract >= cfg.minNetEdgeCents else { return nil }

        // capital = gross cash outlay (Σvwap*Q + fees); the guaranteed payout is the return.
        let outlay = vwapSum * targetQ + totalFees
        let netPct = outlay > 0 ? netAtQ / outlay : 0
        let exp = markets.compactMap(\.expiration).max()
        let days = ScannerMath.daysToSettlement(expiration: exp, now: snap.now)
        let annual = ScannerMath.annualizedPct(netEdgePct: netPct, days: days)

        var warnings: [ScannerWarning] = [.settlementDiscretion]
        if abs(yesSumCents - 100) > Decimal(cfg.lockTilingToleranceCents) {
            warnings.append(.possibleNonTiling(yesSumCents: yesSumCents))
        }
        if minDepth < Decimal(5) { warnings.append(.oneContractMirage(maxQty: minDepth)) }
        if annual < cfg.hurdleAPR * 100 { warnings.append(.belowHurdle(annualizedPct: annual, hurdlePct: cfg.hurdleAPR * 100)) }

        let stamp = markets.map(\.lastUpdate).min() ?? snap.now
        return Opportunity(
            id: Opportunity.makeID(kind: kind, legs: legs), kind: kind, eventTicker: event.eventTicker,
            seriesTicker: event.seriesTicker, title: event.title, category: event.category, legs: legs,
            grossEdgeCents: grossAtQ, totalFeesCents: totalFees, netEdgeCents: netAtQ,
            netEdgePerContractCents: netPerContract, netEdgePct: netPct,
            maxContractsAtPositiveEdge: minDepth, capitalRequiredCents: outlay,
            maxLossIfLeggedOutCents: outlay, daysToSettlement: days, annualizedPct: annual,
            freshnessTimestamp: stamp, freshnessAgeSeconds: snap.now.timeIntervalSince(stamp),
            confidence: markets.count <= 3 ? Decimal(string: "0.9")! : Decimal(string: "0.8")!,
            leggingRisk: markets.count <= 3 ? .moderate : .high, warnings: warnings, isLive: false
        )
    }
}
