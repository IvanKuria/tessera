import Foundation
import NaturalLanguage
import KalshiKit
import PolymarketKit
import ArbEngine

// Headless smoke: verify cross-venue event matching against LIVE Kalshi +
// Polymarket data. Non-GUI proof that EventMatcher finds Kalshi↔Polymarket
// event matches. Mirrors Tessera/Sources/Arb/ArbStore.swift's wire→ref mapping.

let maxKalshiMarkets = 1_000

// MARK: - Discover Kalshi

func discoverKalshi() async throws -> [VenueMarketRef] {
    let client = KalshiClient(environment: .production)
    var refs: [VenueMarketRef] = []
    var cursor: String?
    repeat {
        let resp = try await client.events(
            status: "open", seriesTicker: nil, withNestedMarkets: true, limit: 200, cursor: cursor
        )
        for event in resp.events {
            guard let markets = event.markets else { continue }
            for market in markets where market.status == .active || market.status == .unknown {
                let rules = [market.yesSubTitle, market.subtitle, event.subTitle]
                    .compactMap { $0 }
                    .first { !$0.isEmpty }
                // SPECIFIC title for matching: fold in this market's own outcome
                // label so multi-outcome events align with PM's specific question.
                let outcomeLabel = (market.yesSubTitle ?? market.subtitle ?? "")
                    .trimmingCharacters(in: .whitespaces)
                let isGeneric = outcomeLabel.isEmpty
                    || outcomeLabel.caseInsensitiveCompare("Yes") == .orderedSame
                let matchTitle = isGeneric ? event.title : "\(event.title) \(outcomeLabel)"
                refs.append(VenueMarketRef(
                    id: market.ticker,
                    title: matchTitle,
                    category: event.category,
                    closeDate: market.closeDate,
                    outcomes: ["Yes", "No"],
                    resolutionText: rules
                ))
                if refs.count >= maxKalshiMarkets { return refs }
            }
        }
        cursor = resp.nextCursor
    } while cursor != nil && refs.count < maxKalshiMarkets
    return refs
}

// MARK: - Discover Polymarket

func discoverPolymarket() async throws -> [VenueMarketRef] {
    let gamma = GammaService(client: PMClient())
    let markets = try await gamma.allOpenMarkets(pageLimit: 100, maxPages: 24)
    var refs: [VenueMarketRef] = []
    for m in markets {
        let ref = VenueMarketRef(polymarket: m)
        // Keep only binary markets that carry both CLOB token ids.
        guard ref.isBinary, ref.pmYesTokenID != nil, ref.pmNoTokenID != nil else { continue }
        refs.append(ref)
    }
    return refs
}

// MARK: - Run

func run() async {
    // Debug: is the semantic embedding actually available at runtime? If nil,
    // the matcher falls back to Jaccard for the semantic term.
    let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    print("DEBUG NLEmbedding.sentenceEmbedding(for: .english) == nil? \(embedding == nil)")

    do {
        print("Fetching Kalshi + Polymarket (live)…"); fflush(stdout)
        let t0 = Date()
        async let kTask = discoverKalshi()
        async let pTask = discoverPolymarket()
        let kalshiRefs = try await kTask
        let pmRefs = try await pTask
        print("fetched kalshi=\(kalshiRefs.count) polymarket=\(pmRefs.count) in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s; matching…")
        fflush(stdout)

        let config = MatchConfig(minConfidence: Decimal(string: "0.45")!)
        let t1 = Date()
        let pairs = EventMatcher.match(kalshi: kalshiRefs, polymarket: pmRefs, config: config)
        print("match completed in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
        fflush(stdout)

        print("")
        print("counts: kalshi=\(kalshiRefs.count), polymarket=\(pmRefs.count), matched=\(pairs.count)")

        if pairs.isEmpty {
            // Dig in: how many (kalshi, pm) pairs survived `compatible` pruning
            // before scoring? If this is also ~0, the topic/date gate is the
            // culprit; if it's large, the score threshold is.
            var survived = 0
            for k in kalshiRefs where k.isBinary {
                for p in pmRefs where p.isBinary {
                    if EventMatcher.compatible(k, p, config: config) { survived += 1 }
                }
            }
            print("DEBUG matched=0 — pairs surviving EventMatcher.compatible pruning: \(survived)")
        }

        let sorted = pairs.sorted { $0.confidence > $1.confidence }
        let mismatches = pairs.filter { $0.resolutionMismatch }.count

        print("")
        print("top \(min(15, sorted.count)) matched pairs (confidence | kalshi  <=>  polymarket):")
        for pair in sorted.prefix(15) {
            let conf = NSDecimalNumber(decimal: pair.confidence).doubleValue
            let confStr = String(format: "%.3f", conf)
            print("\(confStr) | \(pair.kalshi.title)  <=>  \(pair.polymarket.title)")
        }

        print("")
        print("matched pairs with resolutionMismatch == true: \(mismatches) / \(pairs.count)")
        fflush(stdout)
    } catch {
        print("SMOKE ERROR: \(error)")
        exit(1)
    }
}

await run()
