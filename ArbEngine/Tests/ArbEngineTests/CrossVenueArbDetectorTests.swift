import XCTest
import KalshiKit
@testable import ArbEngine

final class CrossVenueArbDetectorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ladder(_ price: Int, _ size: Decimal) -> [Ladder.Level] {
        [(price: price, size: size)]
    }

    private func pair(confidence: Decimal = Decimal(string: "0.9")!,
                      mismatch: Bool = false) -> MatchedPair {
        let exp = now.addingTimeInterval(30 * 86_400)
        let k = VenueMarketRef(id: "KXFED-26", title: "Will the Fed cut rates in 2026?",
                               category: "Economics", closeDate: exp)
        let p = VenueMarketRef(id: "0xpm", title: "Will the Fed cut rates in 2026?",
                               category: "Economics", closeDate: exp,
                               pmYesTokenID: "yT", pmNoTokenID: "nT")
        return MatchedPair(kalshi: k, polymarket: p, pmYesTokenID: "yT", pmNoTokenID: "nT",
                           confidence: confidence, resolutionMismatch: mismatch)
    }

    // Kalshi YES 45 + PM NO 45 = 90 → a net-positive lock with two venue-tagged legs.
    func testNetPositiveLockSurfaces() {
        let books = VenueBooks(
            kalshiYesAsk: ladder(45, 200),
            kalshiNoAsk: ladder(60, 200),   // worse orientation
            pmYesAsk: ladder(60, 200),
            pmNoAsk: ladder(45, 200)
        )
        let opp = CrossVenueArbDetector.detect(pair(), books: books,
                                               config: DetectorConfig(), now: now)
        let o = try! XCTUnwrap(opp)
        XCTAssertEqual(o.kind, .edge(.crossVenueArb))
        XCTAssertEqual(o.legs.count, 2)

        let venues = Set(o.legs.compactMap(\.venue))
        XCTAssertEqual(venues, [.kalshi, .polymarket])

        let yesLeg = o.legs.first { $0.side == .yes }!
        let noLeg = o.legs.first { $0.side == .no }!
        XCTAssertEqual(yesLeg.venue, .kalshi)
        XCTAssertEqual(noLeg.venue, .polymarket)
        // PM leg is fee-free.
        XCTAssertEqual(noLeg.feeCents, 0)
        // Gross per set is 100 - 90 = 10¢ → positive net after Kalshi fee.
        XCTAssertGreaterThan(o.netEdgeCents, 0)
        XCTAssertTrue(o.warnings.contains(.crossVenueSettlement))
    }

    // A near-100 pair (49 + 50 = 99) is fee/threshold-killed → nil.
    func testNearHundredKilled() {
        let books = VenueBooks(
            kalshiYesAsk: ladder(49, 200),
            kalshiNoAsk: ladder(80, 200),
            pmYesAsk: ladder(80, 200),
            pmNoAsk: ladder(50, 200)
        )
        var cfg = DetectorConfig()
        cfg.minNetEdgeCents = 1
        let opp = CrossVenueArbDetector.detect(pair(), books: books, config: cfg, now: now)
        XCTAssertNil(opp)
    }

    // resolutionMismatch flows through to the warning list.
    func testResolutionMismatchWarning() {
        let books = VenueBooks(
            kalshiYesAsk: ladder(40, 200),
            kalshiNoAsk: ladder(70, 200),
            pmYesAsk: ladder(70, 200),
            pmNoAsk: ladder(40, 200)
        )
        let opp = CrossVenueArbDetector.detect(pair(mismatch: true), books: books,
                                               config: DetectorConfig(), now: now)
        let o = try! XCTUnwrap(opp)
        XCTAssertTrue(o.warnings.contains(.resolutionMismatch))
    }

    // Low confidence attaches a .lowMatchConfidence warning.
    func testLowConfidenceWarning() {
        let books = VenueBooks(
            kalshiYesAsk: ladder(40, 200),
            kalshiNoAsk: ladder(70, 200),
            pmYesAsk: ladder(70, 200),
            pmNoAsk: ladder(40, 200)
        )
        let lowConf = Decimal(string: "0.6")!
        let opp = CrossVenueArbDetector.detect(pair(confidence: lowConf), books: books,
                                               config: DetectorConfig(), now: now)
        let o = try! XCTUnwrap(opp)
        XCTAssertEqual(o.confidence, lowConf)
        XCTAssertTrue(o.warnings.contains(.lowMatchConfidence(score: lowConf)))
    }

    // Both legs lock above 100 → no orientation clears → nil.
    func testNoLockReturnsNil() {
        let books = VenueBooks(
            kalshiYesAsk: ladder(60, 200),
            kalshiNoAsk: ladder(60, 200),
            pmYesAsk: ladder(60, 200),
            pmNoAsk: ladder(60, 200)
        )
        XCTAssertNil(CrossVenueArbDetector.detect(pair(), books: books,
                                                  config: DetectorConfig(), now: now))
    }

    // The better orientation is chosen when both are net-positive.
    func testPicksBetterOrientation() {
        // Orientation A (K-yes + PM-no): 45 + 45 = 90 → 10¢ gross.
        // Orientation B (PM-yes + K-no): 30 + 30 = 60 → 40¢ gross (richer).
        let books = VenueBooks(
            kalshiYesAsk: ladder(45, 200),
            kalshiNoAsk: ladder(30, 200),
            pmYesAsk: ladder(30, 200),
            pmNoAsk: ladder(45, 200)
        )
        let o = try! XCTUnwrap(CrossVenueArbDetector.detect(pair(), books: books,
                                                            config: DetectorConfig(), now: now))
        let yesLeg = o.legs.first { $0.side == .yes }!
        XCTAssertEqual(yesLeg.venue, .polymarket)  // the 30¢ YES side won
    }
}
