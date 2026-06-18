import XCTest
@testable import PolymarketKit

final class GammaServiceTests: XCTestCase {
    private func loadMarkets() throws -> [PMMarket] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gamma_markets", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try PMJSON.decoder.decode([PMMarket].self, from: data)
    }

    func testDecodesNonEmpty() throws {
        let markets = try loadMarkets()
        XCTAssertFalse(markets.isEmpty)
    }

    func testJSONStringArraysAreUnwrapped() throws {
        let m = try XCTUnwrap(loadMarkets().first)
        // outcomes was a JSON-encoded string like "[\"Yes\",\"No\"]".
        XCTAssertGreaterThanOrEqual(m.outcomes.count, 2)
        // outcomePrices aligns with outcomes and was also a JSON-string array.
        XCTAssertEqual(m.outcomePrices.count, m.outcomes.count)
        // clobTokenIds aligns and every id is a non-empty huge decimal string.
        XCTAssertEqual(m.clobTokenIds.count, m.outcomes.count)
        XCTAssertTrue(m.clobTokenIds.allSatisfy { !$0.isEmpty })
    }

    func testOutcomePricesDecodeAsDecimalsInRange() throws {
        let m = try XCTUnwrap(loadMarkets().first)
        XCTAssertTrue(m.outcomePrices.allSatisfy { $0.value >= 0 && $0.value <= 1 })
    }

    func testCoreFieldsDecoded() throws {
        let m = try XCTUnwrap(loadMarkets().first)
        XCTAssertTrue(m.conditionId.hasPrefix("0x"))
        XCTAssertFalse(m.question.isEmpty)
        XCTAssertFalse(m.slug.isEmpty)
        XCTAssertNotNil(m.endDate)
        XCTAssertFalse(m.closed)
        XCTAssertNotNil(m.volume)
        XCTAssertNotNil(m.liquidity)
    }

    func testCategoryDerivedFromNestedEvent() throws {
        let markets = try loadMarkets()
        // At least one market should carry nested events, from which a
        // best-effort category (the event title) is derived.
        XCTAssertTrue(markets.contains { $0.events?.isEmpty == false })
        if let m = markets.first(where: { $0.events?.first?.title != nil }) {
            XCTAssertEqual(m.category, m.events?.first?.title)
        }
    }

    func testRoundTripEncodeDecode() throws {
        let m = try XCTUnwrap(loadMarkets().first)
        let data = try PMJSON.encoder.encode(m)
        let back = try PMJSON.decoder.decode(PMMarket.self, from: data)
        XCTAssertEqual(back.outcomes, m.outcomes)
        XCTAssertEqual(back.outcomePrices, m.outcomePrices)
        XCTAssertEqual(back.clobTokenIds, m.clobTokenIds)
        XCTAssertEqual(back.conditionId, m.conditionId)
    }
}
