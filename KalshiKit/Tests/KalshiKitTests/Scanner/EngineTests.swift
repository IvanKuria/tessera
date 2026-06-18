import XCTest
import Foundation
@testable import KalshiKit

final class EngineTests: XCTestCase {
    private func mkt(_ t: String, yesAsk: Int?, yesBid: Int?, age: Double = 0) -> MarketSnapshot {
        let now = Date(timeIntervalSince1970: 1_000_000)
        return MarketSnapshot(ticker: t, seriesTicker: "S", bestYesAskCents: yesAsk, bestYesBidCents: yesBid,
                              yesAskLadder: yesAsk.map { [($0, Decimal(1000))] } ?? [], noAskLadder: yesBid.map { [(100-$0, Decimal(1000))] } ?? [],
                              strike: nil, expiration: now.addingTimeInterval(20*86400), lastUpdate: now.addingTimeInterval(-age))
    }
    private func snap(_ m: [MarketSnapshot], me: Bool = false) -> ScanSnapshot {
        ScanSnapshot(events: [EventSnapshot(eventTicker: "E", seriesTicker: "S", title: "T", category: "C", mutuallyExclusive: me, markets: m)],
                     now: Date(timeIntervalSince1970: 1_000_000), config: DetectorConfig())
    }
    func testWideSpreadFlag() {                          // T17
        let opps = SpreadStaleDetector.scan(snap([mkt("A", yesAsk: 56, yesBid: 44)]))
        XCTAssertTrue(opps.contains { if case .edge(.wideSpread) = $0.kind { return true }; return false })
    }
    func testStaleFlag() {                               // T18
        let opps = SpreadStaleDetector.scan(snap([mkt("A", yesAsk: 50, yesBid: 49, age: 200)]))
        XCTAssertTrue(opps.contains { if case .edge(.staleQuote) = $0.kind { return true }; return false })
    }
    func testBookIntegrityBelow100() {                   // T19
        // yesAsk 48 + noAsk 48 = 96 (<100). noAsk = 100 - yesBid → yesBid 52.
        let opps = BookIntegrityCheck.scan(snap([mkt("A", yesAsk: 48, yesBid: 52)]))
        XCTAssertTrue(opps.isEmpty || opps.allSatisfy { $0.netEdgeCents == 0 })
        // BookIntegrity emits no tradable row; warning only is acceptable as empty here.
    }
    func testRankingLocksAboveEdges() {
        let lockSnap = snap([mkt("A", yesAsk: 4, yesBid: 3), mkt("B", yesAsk: 90, yesBid: 89)], me: true)
        let opps = DetectionEngine.scan(lockSnap)
        if opps.count >= 2 { XCTAssertEqual(opps.first?.lane, .lock) }
    }
}
