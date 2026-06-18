import XCTest
import Foundation
@testable import KalshiKit

final class ScannerMathTests: XCTestCase {
    func testFeeMatchesKalshiFeesForWholeContracts() {
        // 50 contracts @ 30¢ taker: ceil(0.07*50*30*70/100)=ceil(73.5)=74
        let f = ScannerMath.feeCents(contracts: 50, priceCents: 30, rate: Decimal(7)/Decimal(100))
        XCTAssertEqual(f, 74)
        XCTAssertEqual(Decimal(KalshiFees.tradingFeeCents(contracts: 50, priceCents: 30, role: .taker)), f)
    }
    func testHalfRateSeriesOverride() {
        // 20 @ 50¢ at 0.035: ceil(0.035*20*50*50/100)=ceil(17.5)=18
        let rate = ScannerMath.feeRate(seriesTicker: "INXD-26", role: .taker, config: DetectorConfig())
        XCTAssertEqual(ScannerMath.feeCents(contracts: 20, priceCents: 50, rate: rate), 18)
    }
    func testVWAPWalksLevels() {
        // target 50 over [(30,20),(31,200)] → (30*20+31*30)/50 = 30.6
        let r = ScannerMath.walk(ladder: [(30, 20), (31, 200)], targetQty: 50)
        XCTAssertEqual(r.vwapCents, Decimal(string: "30.6"))
        XCTAssertEqual(r.filled, 50)
    }
    func testDepthCapsFill() {
        let r = ScannerMath.walk(ladder: [(30, 5)], targetQty: 50)
        XCTAssertEqual(r.filled, 5)
        XCTAssertEqual(r.depthAvailable, 5)
    }
    func testDaysToSettlementFlooredAtHalf() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = now.addingTimeInterval(3600) // 1h
        XCTAssertEqual(ScannerMath.daysToSettlement(expiration: soon, now: now), Decimal(string: "0.5"))
    }
}
