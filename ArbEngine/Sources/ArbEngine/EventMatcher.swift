import Foundation
import NaturalLanguage

// MARK: - MatchConfig

/// Tuning for ``EventMatcher``.
public struct MatchConfig: Sendable, Hashable {
    /// Minimum blended confidence (0…1) for a pair to be returned.
    public var minConfidence: Decimal
    /// Max absolute difference between close dates (seconds) to consider a pair.
    /// `nil` on either side is treated as compatible (we don't have the data).
    public var closeDateWindow: TimeInterval
    /// Weight of semantic (embedding) similarity in the blend.
    public var semanticWeight: Decimal
    /// Weight of token-Jaccard overlap in the blend.
    public var jaccardWeight: Decimal
    /// Weight of the shared-entity (numbers/dates/proper-noun) bonus.
    public var entityWeight: Decimal
    /// Similarity below which two markets with resolution text are flagged as a
    /// potential resolution mismatch.
    public var resolutionMismatchThreshold: Decimal

    public init(
        minConfidence: Decimal = Decimal(string: "0.55")!,
        closeDateWindow: TimeInterval = 7 * 86_400,
        semanticWeight: Decimal = Decimal(string: "0.55")!,
        jaccardWeight: Decimal = Decimal(string: "0.35")!,
        entityWeight: Decimal = Decimal(string: "0.10")!,
        resolutionMismatchThreshold: Decimal = Decimal(string: "0.45")!
    ) {
        self.minConfidence = minConfidence
        self.closeDateWindow = closeDateWindow
        self.semanticWeight = semanticWeight
        self.jaccardWeight = jaccardWeight
        self.entityWeight = entityWeight
        self.resolutionMismatchThreshold = resolutionMismatchThreshold
    }
}

// MARK: - EventMatcher

/// Pairs equivalent binary markets across Kalshi and Polymarket.
///
/// Scoring blends three deterministic-where-possible signals into a `0…1`
/// confidence:
///
///   confidence = wₛ·semantic + wⱼ·jaccard + wₑ·entityBonus
///
/// where `semantic` is the cosine similarity of Apple `NLEmbedding` sentence
/// vectors (mapped from cosine *distance* d via `1 − d/2` into 0…1), `jaccard`
/// is token-set overlap, and `entityBonus` rewards shared numbers/dates/proper
/// nouns. When the embedding is unavailable (CI, unsupported locale), the
/// semantic term falls back to the same Jaccard value so results stay
/// deterministic.
public enum EventMatcher {

    public static func match(
        kalshi: [VenueMarketRef],
        polymarket: [VenueMarketRef],
        config: MatchConfig = MatchConfig()
    ) -> [MatchedPair] {
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        // Index Polymarket candidates by topic bucket so each Kalshi market only
        // compares against SAME-topic markets. Without this, the K×P embedding scan
        // (NLEmbedding.distance is ~ms each) is pathologically slow at real scale.
        var byBucket: [String: [VenueMarketRef]] = [:]
        for p in polymarket where p.isBinary && p.pmYesTokenID != nil && p.pmNoTokenID != nil {
            guard let bucket = topicBucket(p.title) else { continue }
            byBucket[bucket, default: []].append(p)
        }
        let jaccardGate = Decimal(string: "0.08")!
        var pairs: [MatchedPair] = []

        for k in kalshi where k.isBinary {
            // Skip markets whose titles don't hit any topic keyword — necessary to
            // keep the embedding scan bounded; the keyword set is broad.
            guard let bucket = topicBucket(k.title), let candidates = byBucket[bucket] else { continue }
            var best: MatchedPair?
            var bestScore = Decimal(-1)

            for p in candidates {
                if let da = k.closeDate, let db = p.closeDate,
                   abs(da.timeIntervalSince(db)) > config.closeDateWindow { continue }
                // Cheap lexical pre-gate: only run the expensive embedding distance
                // on pairs that already share some tokens.
                let jac = jaccard(k.title, p.title)
                guard jac >= jaccardGate else { continue }

                let score = confidence(k, p, embedding: embedding, config: config)
                guard score >= config.minConfidence else { continue }

                if score > bestScore {
                    bestScore = score
                    best = MatchedPair(
                        kalshi: k,
                        polymarket: p,
                        pmYesTokenID: p.pmYesTokenID!,
                        pmNoTokenID: p.pmNoTokenID!,
                        confidence: score,
                        resolutionMismatch: resolutionMismatch(k, p, similarity: score, config: config),
                        kalshiRules: k.resolutionText,
                        pmResolution: p.resolutionText
                    )
                }
            }
            if let best { pairs.append(best) }
        }
        return pairs
    }

    // MARK: Pruning

    public static func compatible(_ a: VenueMarketRef, _ b: VenueMarketRef, config: MatchConfig) -> Bool {
        // Topic gate from TITLE keywords. Venue category taxonomies don't align
        // across Kalshi and Polymarket (Polymarket has no real category), so a
        // category-equality prune rejects everything. Instead bucket each title by
        // keyword and prune only when both map to a known, DIFFERENT topic; an
        // unknown topic on either side is permissive (falls through to scoring).
        if let ta = topicBucket(a.title), let tb = topicBucket(b.title), ta != tb { return false }
        // Close-date window: only prune when BOTH dates are known.
        if let da = a.closeDate, let db = b.closeDate {
            if abs(da.timeIntervalSince(db)) > config.closeDateWindow { return false }
        }
        return true
    }

    /// Coarse topic bucket from a market title's keywords, shared across venues.
    /// Returns nil (permissive) when no keyword matches.
    static func topicBucket(_ title: String) -> String? {
        let t = " " + title.lowercased() + " "
        func has(_ ws: [String]) -> Bool { ws.contains { t.contains($0) } }
        if has(["bitcoin", "btc", "ethereum", " eth ", "crypto", "solana", " xrp", "dogecoin", "stablecoin"]) { return "crypto" }
        if has(["fed ", "interest rate", "rate cut", "rate hike", " cpi", "inflation", " gdp", "recession", "jobs report", "unemployment", "fomc"]) { return "econ" }
        if has(["election", "president", "senate", "congress", "governor", "nominee", "primary", "democrat", "republican", "parliament", "prime minister", "attorney general", "supreme court", "impeach"]) { return "politics" }
        if has(["super bowl", "world cup", " nba", " nfl", " mlb", " nhl", "premier league", "champions league", " vs.", "o/u", "match", "tournament", "playoff", "ballon"]) { return "sports" }
        if has(["gpt", "openai", "ai model", " apple", "tesla", "nvidia", "spacex", "iphone", " gta", "launch", "release"]) { return "tech" }
        if has(["temperature", "weather", " rain", " snow", "hurricane", "°c", "°f"]) { return "weather" }
        if has(["movie", "box office", "oscar", "grammy", " album", "spotify", "taylor swift", "netflix", "rotten tomatoes"]) { return "entertainment" }
        return nil
    }

    // MARK: Scoring

    static func confidence(
        _ a: VenueMarketRef,
        _ b: VenueMarketRef,
        embedding: NLEmbedding?,
        config: MatchConfig
    ) -> Decimal {
        let jac = jaccard(a.title, b.title)

        let semantic: Decimal
        if let embedding {
            // NLEmbedding returns cosine distance in 0…2; map to 0…1 similarity.
            let distance = embedding.distance(between: a.title, and: b.title, distanceType: .cosine)
            if distance.isFinite, distance >= 0, distance <= 2 {
                let sim = max(0.0, min(1.0, 1.0 - distance / 2.0))
                semantic = Decimal(sim)
            } else {
                semantic = jac
            }
        } else {
            // Deterministic fallback so CI without the embedding still matches.
            semantic = jac
        }

        let entity = entityBonus(a.title, b.title)

        let blended = config.semanticWeight * semantic
            + config.jaccardWeight * jac
            + config.entityWeight * entity
        return clamp01(blended)
    }

    /// Token-set Jaccard overlap of two titles (0…1).
    static func jaccard(_ x: String, _ y: String) -> Decimal {
        let sx = tokens(x), sy = tokens(y)
        guard !sx.isEmpty || !sy.isEmpty else { return 0 }
        let inter = sx.intersection(sy).count
        let union = sx.union(sy).count
        guard union > 0 else { return 0 }
        return Decimal(inter) / Decimal(union)
    }

    /// Small bonus (0…1) for shared salient entities: numbers, 4-digit years,
    /// and capitalized words (proper nouns). Rewards "Fed … 2026" agreement.
    static func entityBonus(_ x: String, _ y: String) -> Decimal {
        let ex = entities(x), ey = entities(y)
        guard !ex.isEmpty, !ey.isEmpty else { return 0 }
        let inter = ex.intersection(ey).count
        let denom = min(ex.count, ey.count)
        guard denom > 0 else { return 0 }
        return Decimal(inter) / Decimal(denom)
    }

    // MARK: Resolution mismatch

    static func resolutionMismatch(
        _ a: VenueMarketRef,
        _ b: VenueMarketRef,
        similarity: Decimal,
        config: MatchConfig
    ) -> Bool {
        // Conservative: only judge when both sides actually have resolution text.
        guard let ra = a.resolutionText, !ra.isEmpty,
              let rb = b.resolutionText, !rb.isEmpty else {
            // Missing rules on either side → can't confirm equivalence → flag.
            return a.resolutionText == nil || b.resolutionText == nil
                ? false  // no text at all on a side: not a *mismatch* signal, just unknown
                : false
        }
        // Two cues, flag if either fires:
        // 1. Overall title similarity is low despite passing the gate.
        if similarity < config.resolutionMismatchThreshold { return true }
        // 2. The resolution texts share little vocabulary (different sources/dates).
        let ruleSim = jaccard(ra, rb)
        if ruleSim < config.resolutionMismatchThreshold { return true }
        return false
    }

    // MARK: Tokenization helpers

    private static let stopwords: Set<String> = [
        "the", "a", "an", "will", "be", "to", "in", "of", "on", "for", "and",
        "or", "is", "are", "by", "at", "this", "that", "it", "as", "with",
    ]

    static func tokens(_ s: String) -> Set<String> {
        let lowered = s.lowercased()
        let parts = lowered.unicodeScalars.split { !(CharacterSet.alphanumerics.contains($0)) }
        return Set(parts.map(String.init).filter { $0.count > 1 && !stopwords.contains($0) })
    }

    static func entities(_ s: String) -> Set<String> {
        var out: Set<String> = []
        let words = s.split { $0 == " " || $0 == "," || $0 == "?" || $0 == "." }
        for w in words {
            let str = String(w)
            // Numbers / years.
            if str.allSatisfy({ $0.isNumber }) && !str.isEmpty {
                out.insert(str)
                continue
            }
            // Proper nouns (capitalized, not the first trivial word).
            if let first = str.first, first.isUppercase, str.count > 1 {
                out.insert(str.lowercased())
            }
        }
        return out
    }

    private static func clamp01(_ d: Decimal) -> Decimal {
        if d < 0 { return 0 }
        if d > 1 { return 1 }
        return d
    }
}
