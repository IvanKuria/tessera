import XCTest
import Foundation
@testable import KalshiKit

final class ScannerModelsTests: XCTestCase {
    func testOpportunityIDIsStableAcrossLegOrder() {
        let a = Leg(marketTicker: "B", side: .yes, priceCents: 30, qty: 10, feeCents: 6, depthAvailable: 100, vwapCents: 30)
        let b = Leg(marketTicker: "A", side: .yes, priceCents: 33, qty: 10, feeCents: 6, depthAvailable: 100, vwapCents: 33)
        let id1 = Opportunity.makeID(kind: .lock(.multiOutcomeUnderround), legs: [a, b])
        let id2 = Opportunity.makeID(kind: .lock(.multiOutcomeUnderround), legs: [b, a])
        XCTAssertEqual(id1, id2, "ID must be order-independent so rescans update in place")
    }
}
