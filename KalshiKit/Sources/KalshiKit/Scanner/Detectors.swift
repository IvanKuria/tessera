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

public enum LadderMonotonicityDetector: Detector {
    public static let detectorID = "ladderMonotonicity"

    public static func scan(_ snapshot: ScanSnapshot) -> [Opportunity] {
        var out: [Opportunity] = []
        for event in snapshot.events {
            // Order by strike (threshold ladder). Require ≥2 with strikes.
            let rungs = event.markets.filter { $0.strike != nil && $0.bestYesAskCents != nil && $0.bestYesBidCents != nil }
                .sorted { ($0.strike ?? 0) < ($1.strike ?? 0) }
            guard rungs.count >= 2 else { continue }
            // Threshold law: P(X>a) >= P(X>b) for a<b → yesAsk should be non-increasing.
            // Violation: a looser (lower-strike) rung's YES ask is cheaper than a tighter (higher-strike) rung's YES bid.
            for i in 0..<rungs.count {
                for j in (i+1)..<rungs.count {
                    let loose = rungs[i], tight = rungs[j]
                    guard let la = loose.bestYesAskCents, let tb = tight.bestYesBidCents else { continue }
                    let noAskT = 100 - tb
                    let floorGross = 100 - la - noAskT          // = tb - la
                    guard floorGross > 0 else { continue }
                    if let o = priceLadder(event: event, loose: loose, tight: tight, looseYesAsk: la, tightNoAsk: noAskT, floorGross: floorGross, snap: snapshot) {
                        out.append(o)
                    }
                }
            }
        }
        return out
    }

    private static func priceLadder(event: EventSnapshot, loose: MarketSnapshot, tight: MarketSnapshot,
                                    looseYesAsk: Int, tightNoAsk: Int, floorGross: Int, snap: ScanSnapshot) -> Opportunity? {
        let cfg = snap.config
        let q = Decimal(cfg.maxStakeContracts)
        let wL = ScannerMath.walk(ladder: loose.yesAskLadder, targetQty: q)
        let wT = ScannerMath.walk(ladder: tight.noAskLadder, targetQty: q)
        let minDepth = min(wL.depthAvailable, wT.depthAvailable)
        let rateL = ScannerMath.feeRate(seriesTicker: loose.seriesTicker, role: cfg.feeRole, config: cfg)
        let rateT = ScannerMath.feeRate(seriesTicker: tight.seriesTicker, role: cfg.feeRole, config: cfg)
        let feeL = ScannerMath.feeCents(contracts: q, priceCents: looseYesAsk, rate: rateL)
        let feeT = ScannerMath.feeCents(contracts: q, priceCents: tightNoAsk, rate: rateT)
        let totalFees = feeL + feeT
        let grossAtQ = Decimal(floorGross) * q
        let netAtQ = grossAtQ - totalFees
        guard netAtQ > 0 else { return nil }                    // floor fee-negative → drop (v1)
        let legs = [
            Leg(marketTicker: loose.ticker, side: .yes, priceCents: looseYesAsk, qty: q, feeCents: feeL, depthAvailable: wL.depthAvailable, vwapCents: wL.vwapCents),
            Leg(marketTicker: tight.ticker, side: .no, priceCents: tightNoAsk, qty: q, feeCents: feeT, depthAvailable: wT.depthAvailable, vwapCents: wT.vwapCents),
        ]
        let outlay = (Decimal(looseYesAsk) + Decimal(tightNoAsk)) * q + totalFees
        let netPct = outlay > 0 ? netAtQ / outlay : 0
        let exp = [loose.expiration, tight.expiration].compactMap { $0 }.max()
        let days = ScannerMath.daysToSettlement(expiration: exp, now: snap.now)
        let stamp = min(loose.lastUpdate, tight.lastUpdate)
        var warnings: [ScannerWarning] = []
        if minDepth < 5 { warnings.append(.oneContractMirage(maxQty: minDepth)) }
        return Opportunity(
            id: Opportunity.makeID(kind: .edge(.ladderMonotonicity), legs: legs), kind: .edge(.ladderMonotonicity),
            eventTicker: event.eventTicker, seriesTicker: event.seriesTicker, title: event.title, category: event.category,
            legs: legs, grossEdgeCents: grossAtQ, totalFeesCents: totalFees, netEdgeCents: netAtQ,
            netEdgePerContractCents: Decimal(floorGross) - totalFees / q, netEdgePct: netPct,
            maxContractsAtPositiveEdge: minDepth, capitalRequiredCents: outlay, maxLossIfLeggedOutCents: outlay,
            daysToSettlement: days, annualizedPct: ScannerMath.annualizedPct(netEdgePct: netPct, days: days),
            freshnessTimestamp: stamp, freshnessAgeSeconds: snap.now.timeIntervalSince(stamp),
            confidence: Decimal(string: "0.6")!, leggingRisk: .moderate, warnings: warnings, isLive: false
        )
    }
}
