import XCTest
import KalshiKit
import PolymarketKit
@testable import ArbEngine

final class LadderTests: XCTestCase {

    // PM probabilities (0…1) map to cents (×100) and sort ascending.
    func testFromPMAsks() {
        let book = PMOrderbook(
            bids: [],
            asks: [PMLevel(price: Decimal(string: "0.60")!, size: 10),
                   PMLevel(price: Decimal(string: "0.45")!, size: 20)]
        )
        let ladder = Ladder.fromPMAsks(book)
        XCTAssertEqual(ladder.map(\.price), [45, 60])
        XCTAssertEqual(ladder.first?.size, 20)
    }

    // Kalshi YES asks come from the derived sell-YES side; NO asks are 100 − yesBid.
    func testFromKalshi() {
        // yesDollars = bids to buy YES → derived NO asks at 100 − p.
        // noDollars  = bids to buy NO  → derived YES asks at 100 − p.
        let ob = Orderbook(
            yesDollars: [["0.55", "100"]],   // YES bid 55 → NO ask 45
            noDollars: [["0.40", "100"]]     // NO bid 40 → YES ask 60
        )
        let built = Ladder.fromKalshi(ob)
        XCTAssertEqual(built.yesAsk.map(\.price), [60])
        XCTAssertEqual(built.noAsk.map(\.price), [45])
    }
}
