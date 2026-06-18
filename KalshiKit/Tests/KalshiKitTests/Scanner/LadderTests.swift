import XCTest
import Foundation
@testable import KalshiKit

final class LadderTests: XCTestCase {
    private func rung(_ t: String, strike: Double, yesAsk: Int, yesBid: Int, depth: Decimal = 1000) -> MarketSnapshot {
        let now = Date(timeIntervalSince1970: 1_000_000)
        return MarketSnapshot(ticker: t, seriesTicker: "BTC", bestYesAskCents: yesAsk, bestYesBidCents: yesBid,
                              yesAskLadder: [(yesAsk, depth)], noAskLadder: [(100 - yesBid, depth)],
                              strike: strike, expiration: now.addingTimeInterval(10*86400), lastUpdate: now)
    }
    private func snap(_ m: [MarketSnapshot]) -> ScanSnapshot {
        ScanSnapshot(events: [EventSnapshot(eventTicker: "E", seriesTicker: "BTC", title: "BTC", category: "Crypto", mutuallyExclusive: false, markets: m)],
                     now: Date(timeIntervalSince1970: 1_000_000), config: DetectorConfig())
    }
    func testCrossedLadderPositiveFloor() {             // T11
        // ">60k" yesAsk 70 cheaper than ">62k" yesBid 74 → crossed by 4; noAsk_T = 26; floor = 100-70-26=4
        let s = snap([rung("L", strike: 60, yesAsk: 70, yesBid: 69), rung("T", strike: 62, yesAsk: 75, yesBid: 74)])
        let opps = LadderMonotonicityDetector.scan(s)
        XCTAssertEqual(opps.count, 1)
        XCTAssertEqual(opps[0].kind, .edge(.ladderMonotonicity))
        XCTAssertGreaterThan(opps[0].netEdgeCents, 0)
    }
    func testThinCrossFeeNegativeDropped() {            // T12
        let s = snap([rung("L", strike: 60, yesAsk: 71, yesBid: 70), rung("T", strike: 62, yesAsk: 73, yesBid: 72)])
        // floor = 100 - 71 - 28 = 1; fees kill it at size → no positive-floor edge
        XCTAssertTrue(LadderMonotonicityDetector.scan(s).allSatisfy { $0.netEdgeCents <= 0 } || LadderMonotonicityDetector.scan(s).isEmpty)
    }
    func testMonotoneLadderNoViolation() {              // T14
        let s = snap([rung("A", strike: 60, yesAsk: 80, yesBid: 79), rung("B", strike: 62, yesAsk: 60, yesBid: 59), rung("C", strike: 64, yesAsk: 40, yesBid: 39)])
        XCTAssertTrue(LadderMonotonicityDetector.scan(s).isEmpty)
    }
}
