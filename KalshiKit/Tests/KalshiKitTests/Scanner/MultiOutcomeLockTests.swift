import XCTest
import Foundation
@testable import KalshiKit

final class MultiOutcomeLockTests: XCTestCase {
    private func mkt(_ t: String, yesAsk: Int?, yesBid: Int?, depth: Decimal = 1000, exp: TimeInterval = 30*86400) -> MarketSnapshot {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let yesLad = yesAsk.map { [(price: $0, size: depth)] } ?? []
        let noLad = yesBid.map { [(price: 100 - $0, size: depth)] } ?? []
        return MarketSnapshot(ticker: t, seriesTicker: "S", bestYesAskCents: yesAsk, bestYesBidCents: yesBid,
                              yesAskLadder: yesLad, noAskLadder: noLad, strike: nil,
                              expiration: now.addingTimeInterval(exp), lastUpdate: now)
    }
    private func snap(_ markets: [MarketSnapshot], me: Bool = true, config: DetectorConfig = DetectorConfig()) -> ScanSnapshot {
        ScanSnapshot(events: [EventSnapshot(eventTicker: "E", seriesTicker: "S", title: "T", category: "Politics", mutuallyExclusive: me, markets: markets)],
                     now: Date(timeIntervalSince1970: 1_000_000), config: config)
    }

    func testThinMidLockIsFeeKilledAndDropped() {            // T1
        let s = snap([mkt("A", yesAsk: 30, yesBid: 29), mkt("B", yesAsk: 33, yesBid: 32), mkt("C", yesAsk: 34, yesBid: 33)])
        XCTAssertTrue(MultiOutcomeLockDetector.scan(s).isEmpty)
    }
    func testExtremePriceLockSurvives() {                    // T2
        let s = snap([mkt("A", yesAsk: 4, yesBid: 3), mkt("B", yesAsk: 90, yesBid: 89, exp: 20*86400)])
        let opps = MultiOutcomeLockDetector.scan(s)
        XCTAssertEqual(opps.count, 1)
        XCTAssertGreaterThan(opps[0].netEdgeCents, 0)
        XCTAssertEqual(opps[0].kind, .lock(.multiOutcomeUnderround))
    }
    func testNotMutuallyExclusiveEmitsNothing() {            // T9
        let s = snap([mkt("A", yesAsk: 30, yesBid: 29), mkt("B", yesAsk: 33, yesBid: 32)], me: false)
        XCTAssertTrue(MultiOutcomeLockDetector.scan(s).isEmpty)
    }
    func testSumFarBelow100IsRejectedNotAFakeLock() {        // T4 (corrected)
        // Σ yesAsk = 60 (gap 40 ≫ maxLockGap) ⇒ outcomes missing / non-tiling.
        // This must NOT surface as a giant fake +40¢ "lock" — reject it.
        let s = snap([mkt("A", yesAsk: 20, yesBid: 19), mkt("B", yesAsk: 20, yesBid: 19), mkt("C", yesAsk: 20, yesBid: 19)])
        XCTAssertTrue(MultiOutcomeLockDetector.scan(s).isEmpty)
    }
    func testOverroundBuyNoAll() {                           // T8
        // yesBid {54,52} => Σ=106>100, gap 6 (within maxLockGap) → real overround;
        // noAsk = {46,48}; gross = 100*(2-1) - 94 = 6.
        let s = snap([mkt("A", yesAsk: 56, yesBid: 54), mkt("B", yesAsk: 54, yesBid: 52)])
        let opps = MultiOutcomeLockDetector.scan(s)
        XCTAssertTrue(opps.contains { $0.kind == .lock(.multiOutcomeOverround) })
    }
}
