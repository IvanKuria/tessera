import XCTest
@testable import KalshiKit

/// Decoding tests run against **real** keyless JSON captured live from the
/// production API (June 2026), so they validate the models against the actual
/// wire format rather than hand-written assumptions.
final class DecodingTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    func testDecodesExchangeStatus() throws {
        let status = try KalshiJSON.decoder.decode(ExchangeStatus.self, from: fixture("exchange_status"))
        XCTAssertEqual(status.exchangeActive, true)
        XCTAssertEqual(status.tradingActive, true)
    }

    func testDecodesMarkets() throws {
        let response = try KalshiJSON.decoder.decode(MarketListResponse.self, from: fixture("markets"))
        XCTAssertFalse(response.markets.isEmpty)
        let market = try XCTUnwrap(response.markets.first)
        XCTAssertFalse(market.ticker.isEmpty)
        // Verified live: an open, tradeable market reports "active".
        XCTAssertEqual(market.status, .active)
        XCTAssertTrue(market.status.isOpen)
        // Prices arrive as dollar strings → KalshiDecimal (never Double).
        XCTAssertNotNil(market.yesAskDollars)
        // CursorPaged projection works.
        XCTAssertEqual(response.items.count, response.markets.count)
    }

    func testDecodesEventsWithNestedMarkets() throws {
        let response = try KalshiJSON.decoder.decode(EventListResponse.self, from: fixture("events"))
        XCTAssertFalse(response.events.isEmpty)
        let event = try XCTUnwrap(response.events.first)
        XCTAssertFalse(event.eventTicker.isEmpty)
        // We requested with_nested_markets=true, so markets should be present.
        if let markets = event.markets, let m = markets.first {
            XCTAssertFalse(m.ticker.isEmpty)
        }
    }

    func testDecodesSeries() throws {
        // /series returns {"series":[...]}; the client unwraps to [Series].
        struct Wrapper: Decodable { let series: [Series] }
        let wrapper = try KalshiJSON.decoder.decode(Wrapper.self, from: fixture("series"))
        XCTAssertFalse(wrapper.series.isEmpty)
        let s = try XCTUnwrap(wrapper.series.first)
        XCTAssertFalse(s.ticker.isEmpty)
        XCTAssertFalse(s.title.isEmpty)
    }

    func testDecodesTrades() throws {
        let response = try KalshiJSON.decoder.decode(TradeListResponse.self, from: fixture("trades"))
        let trade = try XCTUnwrap(response.trades.first)
        XCTAssertFalse(trade.ticker.isEmpty)
        // Verified live: trades use count_fp + *_price_dollars strings.
        XCTAssertNotNil(trade.countFp)
        XCTAssertTrue(trade.yesPriceDollars != nil || trade.noPriceDollars != nil)
    }
}
