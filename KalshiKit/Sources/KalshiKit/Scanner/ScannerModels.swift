import Foundation

public enum OpportunityLane: String, Codable, Sendable, Hashable { case lock, edge }

public enum OpportunityKind: Codable, Sendable, Hashable {
    case lock(LockSubtype)
    case edge(EdgeSubtype)
    public enum LockSubtype: String, Codable, Sendable, Hashable { case multiOutcomeUnderround, multiOutcomeOverround }
    public enum EdgeSubtype: String, Codable, Sendable, Hashable { case ladderMonotonicity, wideSpread, staleQuote }

    public var lane: OpportunityLane {
        switch self { case .lock: return .lock; case .edge: return .edge }
    }
    public var rawKey: String {
        switch self {
        case .lock(let s): return "lock.\(s.rawValue)"
        case .edge(let s): return "edge.\(s.rawValue)"
        }
    }
}

public enum Side: String, Codable, Sendable, Hashable { case yes, no }
public enum LeggingRisk: String, Codable, Sendable, Hashable { case none, low, moderate, high }

public enum ScannerWarning: Codable, Sendable, Hashable {
    case feeKilledNearMid
    case oneContractMirage(maxQty: Decimal)
    case wideSpread(cents: Int)
    case staleQuote(ageSeconds: Double)
    case belowHurdle(annualizedPct: Decimal, hurdlePct: Decimal)
    case possibleNonTiling(yesSumCents: Decimal)
    case settlementDiscretion
    case bookIntegrity(yesPlusNoCents: Decimal)
    case thinDepth(available: Decimal)
}

public struct Leg: Codable, Sendable, Hashable {
    public let marketTicker: String
    public let side: Side
    public let priceCents: Int
    public let qty: Decimal
    public let feeCents: Decimal
    public let depthAvailable: Decimal
    public let vwapCents: Decimal
    public init(marketTicker: String, side: Side, priceCents: Int, qty: Decimal, feeCents: Decimal, depthAvailable: Decimal, vwapCents: Decimal) {
        self.marketTicker = marketTicker; self.side = side; self.priceCents = priceCents
        self.qty = qty; self.feeCents = feeCents; self.depthAvailable = depthAvailable; self.vwapCents = vwapCents
    }
}

public struct Opportunity: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let kind: OpportunityKind
    public let eventTicker: String
    public let seriesTicker: String?
    public let title: String
    public let category: String?
    public let legs: [Leg]
    public let grossEdgeCents: Decimal
    public let totalFeesCents: Decimal
    public let netEdgeCents: Decimal
    public let netEdgePerContractCents: Decimal
    public let netEdgePct: Decimal
    public let maxContractsAtPositiveEdge: Decimal
    public let capitalRequiredCents: Decimal
    public let maxLossIfLeggedOutCents: Decimal
    public let daysToSettlement: Decimal
    public let annualizedPct: Decimal
    public var freshnessTimestamp: Date
    public var freshnessAgeSeconds: Double
    public let confidence: Decimal
    public let leggingRisk: LeggingRisk
    public let warnings: [ScannerWarning]
    public var isLive: Bool

    public var lane: OpportunityLane { kind.lane }

    public init(
        id: String, kind: OpportunityKind, eventTicker: String, seriesTicker: String?, title: String,
        category: String?, legs: [Leg], grossEdgeCents: Decimal, totalFeesCents: Decimal, netEdgeCents: Decimal,
        netEdgePerContractCents: Decimal, netEdgePct: Decimal, maxContractsAtPositiveEdge: Decimal,
        capitalRequiredCents: Decimal, maxLossIfLeggedOutCents: Decimal, daysToSettlement: Decimal,
        annualizedPct: Decimal, freshnessTimestamp: Date, freshnessAgeSeconds: Double, confidence: Decimal,
        leggingRisk: LeggingRisk, warnings: [ScannerWarning], isLive: Bool
    ) {
        self.id = id; self.kind = kind; self.eventTicker = eventTicker; self.seriesTicker = seriesTicker
        self.title = title; self.category = category; self.legs = legs; self.grossEdgeCents = grossEdgeCents
        self.totalFeesCents = totalFeesCents; self.netEdgeCents = netEdgeCents
        self.netEdgePerContractCents = netEdgePerContractCents; self.netEdgePct = netEdgePct
        self.maxContractsAtPositiveEdge = maxContractsAtPositiveEdge; self.capitalRequiredCents = capitalRequiredCents
        self.maxLossIfLeggedOutCents = maxLossIfLeggedOutCents; self.daysToSettlement = daysToSettlement
        self.annualizedPct = annualizedPct; self.freshnessTimestamp = freshnessTimestamp
        self.freshnessAgeSeconds = freshnessAgeSeconds; self.confidence = confidence
        self.leggingRisk = leggingRisk; self.warnings = warnings; self.isLive = isLive
    }

    public static func makeID(kind: OpportunityKind, legs: [Leg]) -> String {
        let key = legs.map { "\($0.marketTicker):\($0.side.rawValue)" }.sorted().joined(separator: "+")
        return "\(kind.rawKey)|\(key)"
    }
}

public struct DetectorConfig: Sendable, Hashable {
    public var feeRole: KalshiFees.Role
    public var maxStakeContracts: Int
    public var minNetEdgeCents: Decimal
    public var hurdleAPR: Decimal
    public var kalshiCollateralAPY: Decimal
    public var staleQuoteSeconds: Double
    public var wideSpreadCents: Int
    public var lockTilingToleranceCents: Int
    public var halfRateSeriesPrefixes: [String]
    public init(
        feeRole: KalshiFees.Role = .taker,
        maxStakeContracts: Int = 100,
        minNetEdgeCents: Decimal = 1,
        hurdleAPR: Decimal = 0.005,
        kalshiCollateralAPY: Decimal = 0.0325,
        staleQuoteSeconds: Double = 120,
        wideSpreadCents: Int = 8,
        lockTilingToleranceCents: Int = 5,
        halfRateSeriesPrefixes: [String] = ["INX", "NASDAQ100"]
    ) {
        self.feeRole = feeRole; self.maxStakeContracts = maxStakeContracts
        self.minNetEdgeCents = minNetEdgeCents; self.hurdleAPR = hurdleAPR
        self.kalshiCollateralAPY = kalshiCollateralAPY; self.staleQuoteSeconds = staleQuoteSeconds
        self.wideSpreadCents = wideSpreadCents; self.lockTilingToleranceCents = lockTilingToleranceCents
        self.halfRateSeriesPrefixes = halfRateSeriesPrefixes
    }
}

/// One market's executable state, distilled to integer-cent quotes + L2 ask ladders.
public struct MarketSnapshot: Sendable, Hashable {
    public let ticker: String
    public let seriesTicker: String?
    public let bestYesAskCents: Int?
    public let bestYesBidCents: Int?
    /// Ascending YES-ask ladder for buying YES: (priceCents, size).
    public let yesAskLadder: [(price: Int, size: Decimal)]
    /// Ascending NO-ask ladder for buying NO (derived = 100 − yesBid levels): (priceCents, size).
    public let noAskLadder: [(price: Int, size: Decimal)]
    public let strike: Double?
    public let expiration: Date?
    public let lastUpdate: Date

    public var bestNoAskCents: Int? { bestYesBidCents.map { 100 - $0 } }

    public init(ticker: String, seriesTicker: String?, bestYesAskCents: Int?, bestYesBidCents: Int?,
                yesAskLadder: [(price: Int, size: Decimal)], noAskLadder: [(price: Int, size: Decimal)],
                strike: Double?, expiration: Date?, lastUpdate: Date) {
        self.ticker = ticker; self.seriesTicker = seriesTicker
        self.bestYesAskCents = bestYesAskCents; self.bestYesBidCents = bestYesBidCents
        self.yesAskLadder = yesAskLadder; self.noAskLadder = noAskLadder
        self.strike = strike; self.expiration = expiration; self.lastUpdate = lastUpdate
    }
    public static func == (l: MarketSnapshot, r: MarketSnapshot) -> Bool {
        l.ticker == r.ticker && l.bestYesAskCents == r.bestYesAskCents && l.bestYesBidCents == r.bestYesBidCents
            && l.lastUpdate == r.lastUpdate
    }
    public func hash(into h: inout Hasher) { h.combine(ticker); h.combine(lastUpdate) }
}

public struct EventSnapshot: Sendable {
    public let eventTicker: String
    public let seriesTicker: String?
    public let title: String
    public let category: String?
    public let mutuallyExclusive: Bool
    public let markets: [MarketSnapshot]
    public init(eventTicker: String, seriesTicker: String?, title: String, category: String?, mutuallyExclusive: Bool, markets: [MarketSnapshot]) {
        self.eventTicker = eventTicker; self.seriesTicker = seriesTicker; self.title = title
        self.category = category; self.mutuallyExclusive = mutuallyExclusive; self.markets = markets
    }
}

public struct ScanSnapshot: Sendable {
    public let events: [EventSnapshot]
    public let now: Date
    public let config: DetectorConfig
    public init(events: [EventSnapshot], now: Date, config: DetectorConfig) {
        self.events = events; self.now = now; self.config = config
    }
}
