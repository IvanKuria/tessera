import XCTest
@testable import PolymarketKit

final class ClobServiceTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDecodesBookWithLevels() throws {
        let book = try PMOrderbook.decode(from: fixture("clob_book"))
        XCTAssertFalse(book.bids.isEmpty)
        XCTAssertFalse(book.asks.isEmpty)
    }

    func testBookPricesAreDecimalsInRange() throws {
        let book = try PMOrderbook.decode(from: fixture("clob_book"))
        for level in book.bids + book.asks {
            XCTAssertGreaterThanOrEqual(level.price, 0)
            XCTAssertLessThanOrEqual(level.price, 1)
            XCTAssertGreaterThan(level.size, 0)
        }
    }

    func testBestBidIsMaxAndBestAskIsMin() throws {
        let book = try PMOrderbook.decode(from: fixture("clob_book"))
        let bid = try XCTUnwrap(book.bestBid)
        let ask = try XCTUnwrap(book.bestAsk)
        // Computed defensively via max/min regardless of wire ordering.
        XCTAssertEqual(bid, book.bids.map(\.price).max())
        XCTAssertEqual(ask, book.asks.map(\.price).min())
        XCTAssertGreaterThanOrEqual(bid, 0)
        XCTAssertLessThanOrEqual(ask, 1)
    }

    func testDecodesPrice() throws {
        struct W: Decodable { let price: PMDecimal }
        let w = try PMJSON.decoder.decode(W.self, from: fixture("clob_price"))
        XCTAssertGreaterThanOrEqual(w.price.value, 0)
        XCTAssertLessThanOrEqual(w.price.value, 1)
    }

    func testDecodesMidpoint() throws {
        struct W: Decodable { let mid: PMDecimal }
        let w = try PMJSON.decoder.decode(W.self, from: fixture("clob_midpoint"))
        XCTAssertGreaterThanOrEqual(w.mid.value, 0)
        XCTAssertLessThanOrEqual(w.mid.value, 1)
    }
}
