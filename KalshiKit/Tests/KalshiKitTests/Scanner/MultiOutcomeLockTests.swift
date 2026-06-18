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
    func testNonTilingWarningWhenSumFarBelow100() {          // T4
        let s = snap([mkt("A", yesAsk: 20, yesBid: 19), mkt("B", yesAsk: 20, yesBid: 19), mkt("C", yesAsk: 20, yesBid: 19)])
        let opps = MultiOutcomeLockDetector.scan(s)
        XCTAssertEqual(opps.count, 1)
        XCTAssertTrue(opps[0].warnings.contains { if case .possibleNonTiling = $0 { return true }; return false })
    }
    func testOverroundBuyNoAll() {                           // T8
        // yesBid {60,55} => Σ=115>100 → overround; noAsk = {40,45}; gross = 100*(2-1) - 85 = 15
        let s = snap([mkt("A", yesAsk: 62, yesBid: 60), mkt("B", yesAsk: 57, yesBid: 55)])
        let opps = MultiOutcomeLockDetector.scan(s)
        XCTAssertTrue(opps.contains { $0.kind == .lock(.multiOutcomeOverround) })
    }
}
