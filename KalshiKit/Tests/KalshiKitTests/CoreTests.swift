import XCTest
@testable import KalshiKit

final class CoreTests: XCTestCase {

    func testKalshiDecimalParsesDollarStrings() throws {
        struct Box: Decodable { let v: KalshiDecimal }
        let box = try KalshiJSON.decoder.decode(Box.self, from: Data(#"{"v":"0.5600"}"#.utf8))
        XCTAssertEqual(box.v.value, Decimal(string: "0.56"))
        // No binary-float error: exactly 0.56.
        XCTAssertEqual(box.v.value, Decimal(56) / Decimal(100))
    }

    func testKalshiDecimalToleratesNumericForm() throws {
        struct Box: Decodable { let v: KalshiDecimal }
        let box = try KalshiJSON.decoder.decode(Box.self, from: Data(#"{"v":0.56}"#.utf8))
        XCTAssertEqual(box.v.doubleValue, 0.56, accuracy: 0.0001)
    }

    func testUnknownEnumValuesFallBack() throws {
        struct Box: Decodable { let s: MarketStatus; let r: OrderSide }
        let box = try KalshiJSON.decoder.decode(Box.self, from: Data(#"{"s":"some_future_status","r":"weird"}"#.utf8))
        XCTAssertEqual(box.s, .unknown)
        XCTAssertEqual(box.r, .unknown)
    }

    func testEnvironmentBaseURLsAreCorrect() {
        XCTAssertEqual(KalshiEnvironment.production.restBaseURL.absoluteString,
                       "https://api.elections.kalshi.com/trade-api/v2")
        XCTAssertEqual(KalshiEnvironment.demo.restBaseURL.absoluteString,
                       "https://demo-api.kalshi.co/trade-api/v2")
        XCTAssertEqual(KalshiEnvironment.production.signingPathPrefix, "/trade-api/v2")
    }

    func testCursorPagedNormalizesEmptyCursor() {
        XCTAssertNil(MarketListResponse(markets: [], cursor: "").nextCursor)
        XCTAssertEqual(MarketListResponse(markets: [], cursor: "abc").nextCursor, "abc")
    }

    /// `collect` should loop pages until the cursor is exhausted.
    func testCollectPaginatesUntilCursorEmpty() async throws {
        let client = KalshiClient(environment: .demo)
        actor Pager {
            var calls = 0
            func next() -> MarketListResponse {
                calls += 1
                switch calls {
                case 1: return MarketListResponse(markets: [Self.stub("A")], cursor: "p2")
                case 2: return MarketListResponse(markets: [Self.stub("B")], cursor: "p3")
                default: return MarketListResponse(markets: [Self.stub("C")], cursor: nil)
                }
            }
            static func stub(_ t: String) -> Market { Market(ticker: t, eventTicker: "E") }
        }
        let pager = Pager()
        let all = try await client.collect { _ in await pager.next() }
        XCTAssertEqual(all.map(\.ticker), ["A", "B", "C"])
    }

    // MARK: - Trading fees

    func testTakerFeeRoundsUpAtFiftyCents() {
        // 0.07 × 1 × 0.50 × 0.50 = $0.0175 = 1.75¢ → round_up → 2¢.
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 1, priceCents: 50, role: .taker), 2)
    }

    func testMakerFeeIsLowerThanTaker() {
        // 0.0175 × 1 × 0.25 = $0.004375 = 0.4375¢ → round_up → 1¢.
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 1, priceCents: 50, role: .maker), 1)
        XCTAssertLessThan(
            KalshiFees.tradingFeeCents(contracts: 100, priceCents: 50, role: .maker),
            KalshiFees.tradingFeeCents(contracts: 100, priceCents: 50, role: .taker)
        )
    }

    func testFeeHitsExactCentBoundaryWithoutFloatDrift() {
        // 0.07 × 100 × 0.50 × 0.50 = $1.75 = 175¢ exactly — no rounding up.
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 100, priceCents: 50, role: .taker), 175)
        // 0.0175 × 100 × 0.25 = $0.4375 = 43.75¢ → round_up → 44¢.
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 100, priceCents: 50, role: .maker), 44)
    }

    func testFeePeaksAtFiftyCentsAndShrinksTowardExtremes() {
        let mid = KalshiFees.tradingFeeCents(contracts: 1000, priceCents: 50)
        let near = KalshiFees.tradingFeeCents(contracts: 1000, priceCents: 90)
        let edge = KalshiFees.tradingFeeCents(contracts: 1000, priceCents: 99)
        XCTAssertGreaterThan(mid, near)
        XCTAssertGreaterThan(near, edge)
        // Symmetric about 50¢: P and (100−P) cost the same.
        XCTAssertEqual(
            KalshiFees.tradingFeeCents(contracts: 1000, priceCents: 30),
            KalshiFees.tradingFeeCents(contracts: 1000, priceCents: 70)
        )
    }

    func testFeeIsZeroForNoExposureOrInvalidPrice() {
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 0, priceCents: 50), 0)
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: -5, priceCents: 50), 0)
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 10, priceCents: 0), 0)
        XCTAssertEqual(KalshiFees.tradingFeeCents(contracts: 10, priceCents: 100), 0)
    }
}
