import XCTest
import KalshiKit
@testable import ArbEngine

final class EventMatcherTests: XCTestCase {

    private func kalshi(_ title: String, id: String = "K", rules: String? = nil,
                        category: String? = "Economics", date: Date? = nil) -> VenueMarketRef {
        VenueMarketRef(id: id, title: title, category: category, closeDate: date,
                       outcomes: ["Yes", "No"], resolutionText: rules)
    }

    private func poly(_ title: String, id: String = "P", rules: String? = nil,
                      category: String? = "Economics", date: Date? = nil) -> VenueMarketRef {
        VenueMarketRef(id: id, title: title, category: category, closeDate: date,
                       outcomes: ["Yes", "No"], resolutionText: rules,
                       pmYesTokenID: "yes-\(id)", pmNoTokenID: "no-\(id)")
    }

    // Equivalent markets should match above threshold.
    func testEquivalentPairMatches() {
        let k = kalshi("Will the Fed cut rates in 2026?")
        let p = poly("Will the Fed cut rates in 2026?")
        let pairs = EventMatcher.match(kalshi: [k], polymarket: [p])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertGreaterThanOrEqual(pairs[0].confidence, MatchConfig().minConfidence)
        XCTAssertEqual(pairs[0].pmYesTokenID, "yes-P")
        XCTAssertEqual(pairs[0].pmNoTokenID, "no-P")
    }

    // Unrelated markets should not match (false-positive guard).
    func testUnrelatedPairDoesNotMatch() {
        let k = kalshi("Will the Fed cut rates in 2026?")
        let p = poly("Will it rain in NYC tomorrow?", category: "Weather")
        let pairs = EventMatcher.match(kalshi: [k], polymarket: [p])
        XCTAssertTrue(pairs.isEmpty)
    }

    // Relative ordering holds regardless of whether NLEmbedding is present:
    // an equivalent title must outscore an unrelated one.
    func testScoreOrdering() {
        let k = kalshi("Will the Fed cut rates in 2026?")
        let same = poly("Will the Fed cut rates in 2026?")
        let different = poly("Will it rain in NYC tomorrow?", id: "P2")
        let cfg = MatchConfig()
        let simSame = EventMatcher.confidence(k, same, embedding: nil, config: cfg)
        let simDiff = EventMatcher.confidence(k, different, embedding: nil, config: cfg)
        XCTAssertGreaterThan(simSame, simDiff)
        XCTAssertGreaterThanOrEqual(simSame, cfg.minConfidence)
        XCTAssertLessThan(simDiff, cfg.minConfidence)
    }

    // Jaccard fallback path is deterministic.
    func testJaccardFallbackDeterministic() {
        let a = EventMatcher.jaccard("Will the Fed cut rates in 2026?",
                                     "Will the Fed cut rates in 2026?")
        XCTAssertEqual(a, 1)
        let b = EventMatcher.jaccard("Fed cut rates", "rain NYC tomorrow")
        XCTAssertEqual(b, 0)
    }

    // Best match per Kalshi market: only the closest of several polys is returned.
    func testBestMatchPerKalshiMarket() {
        let k = kalshi("Will the Fed cut rates in 2026?")
        let close = poly("Will the Fed cut rates in 2026?", id: "close")
        let loose = poly("Will the Fed cut interest rates this year?", id: "loose")
        let pairs = EventMatcher.match(kalshi: [k], polymarket: [loose, close])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].polymarket.id, "close")
    }

    // Category mismatch prunes the pair before scoring.
    func testCategoryPruning() {
        let k = kalshi("Will the Fed cut rates in 2026?", category: "Economics")
        let p = poly("Will the Fed cut rates in 2026?", category: "Sports")
        XCTAssertFalse(EventMatcher.compatible(k, p, config: MatchConfig()))
    }

    // Close-date window prunes far-apart resolution dates.
    func testCloseDateWindowPruning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let k = kalshi("Will the Fed cut rates in 2026?", date: now)
        let far = poly("Will the Fed cut rates in 2026?", date: now.addingTimeInterval(60 * 86_400))
        XCTAssertFalse(EventMatcher.compatible(k, far, config: MatchConfig()))
        let near = poly("Will the Fed cut rates in 2026?", date: now.addingTimeInterval(86_400))
        XCTAssertTrue(EventMatcher.compatible(k, near, config: MatchConfig()))
    }

    // Resolution mismatch: both have rules but they share little vocabulary.
    func testResolutionMismatchFlag() {
        let k = kalshi("Will the Fed cut rates in 2026?",
                       rules: "Resolves YES if the FOMC lowers the target federal funds rate.")
        let p = poly("Will the Fed cut rates in 2026?",
                     rules: "Settles based on Polymarket UMA oracle vote about ECB decisions.")
        let pairs = EventMatcher.match(kalshi: [k], polymarket: [p])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].resolutionMismatch)
    }

    // Non-binary markets are excluded in v1.
    func testNonBinaryExcluded() {
        let k = VenueMarketRef(id: "K", title: "Who wins?", category: "Sports",
                               outcomes: ["A", "B", "C"])
        let p = poly("Who wins?", category: "Sports")
        XCTAssertTrue(EventMatcher.match(kalshi: [k], polymarket: [p]).isEmpty)
    }
}
