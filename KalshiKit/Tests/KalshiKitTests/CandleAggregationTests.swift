import XCTest
@testable import KalshiKit

final class CandleAggregationTests: XCTestCase {

    /// Build a minute candle whose trade-price OHLC and volume are set. Prices
    /// are passed as exact decimal strings to avoid binary-float error in the
    /// expectations (money is never built from `Double` literals).
    private func candle(
        ts: Int,
        open: String,
        high: String,
        low: String,
        close: String,
        volume: Decimal? = nil
    ) -> Candlestick {
        Candlestick(
            endPeriodTs: ts,
            volumeFp: volume.map(KalshiDecimal.init),
            price: Candlestick.OHLC(
                openDollars: KalshiDecimal(string: open),
                highDollars: KalshiDecimal(string: high),
                lowDollars: KalshiDecimal(string: low),
                closeDollars: KalshiDecimal(string: close)
            )
        )
    }

    func testThreeMinutesIntoOneBucket() {
        // Bucket [0, 300): timestamps 60, 120, 180 all floor to 0.
        let input = [
            candle(ts: 60,  open: "0.50", high: "0.55", low: "0.48", close: "0.52"),
            candle(ts: 120, open: "0.52", high: "0.60", low: "0.51", close: "0.58"),
            candle(ts: 180, open: "0.58", high: "0.59", low: "0.45", close: "0.47"),
        ]

        let result = CandleAggregation.aggregate(input, bucketMinutes: 5)

        XCTAssertEqual(result.count, 1)
        let bucket = result[0]
        XCTAssertEqual(bucket.endPeriodTs, 300) // end of [0, 300) bucket
        XCTAssertEqual(bucket.price?.openDollars?.value, Decimal(string: "0.50"))
        XCTAssertEqual(bucket.price?.highDollars?.value, Decimal(string: "0.60"))
        XCTAssertEqual(bucket.price?.lowDollars?.value, Decimal(string: "0.45"))
        XCTAssertEqual(bucket.price?.closeDollars?.value, Decimal(string: "0.47"))
    }

    func testSplitAtBoundary() {
        let input = [
            candle(ts: 60,  open: "0.50", high: "0.55", low: "0.48", close: "0.52"), // bucket 0
            candle(ts: 240, open: "0.52", high: "0.60", low: "0.51", close: "0.58"), // bucket 0
            candle(ts: 360, open: "0.58", high: "0.62", low: "0.57", close: "0.61"), // bucket 300
            candle(ts: 540, open: "0.61", high: "0.63", low: "0.40", close: "0.42"), // bucket 300
        ]

        let result = CandleAggregation.aggregate(input, bucketMinutes: 5)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].endPeriodTs, 300)
        XCTAssertEqual(result[1].endPeriodTs, 600)

        // First bucket spans ts 60 & 240.
        XCTAssertEqual(result[0].price?.openDollars?.value, Decimal(string: "0.50"))
        XCTAssertEqual(result[0].price?.closeDollars?.value, Decimal(string: "0.58"))
        XCTAssertEqual(result[0].price?.highDollars?.value, Decimal(string: "0.60"))
        XCTAssertEqual(result[0].price?.lowDollars?.value, Decimal(string: "0.48"))

        // Second bucket spans ts 360 & 540.
        XCTAssertEqual(result[1].price?.openDollars?.value, Decimal(string: "0.58"))
        XCTAssertEqual(result[1].price?.closeDollars?.value, Decimal(string: "0.42"))
        XCTAssertEqual(result[1].price?.highDollars?.value, Decimal(string: "0.63"))
        XCTAssertEqual(result[1].price?.lowDollars?.value, Decimal(string: "0.40"))
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertTrue(CandleAggregation.aggregate([], bucketMinutes: 5).isEmpty)
    }

    func testVolumeSumsAcrossBucket() {
        let input = [
            candle(ts: 60,  open: "0.50", high: "0.55", low: "0.48", close: "0.52", volume: 100),
            candle(ts: 120, open: "0.52", high: "0.60", low: "0.51", close: "0.58", volume: 250),
            candle(ts: 180, open: "0.58", high: "0.59", low: "0.45", close: "0.47", volume: 75),
        ]

        let result = CandleAggregation.aggregate(input, bucketMinutes: 5)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].volumeFp?.value, Decimal(425))
    }

    func testGapsAreNotSynthesized() {
        // ts 60 -> bucket 0; ts 1860 (= 31 min) -> bucket 1800. Buckets in
        // between (300, 600, ... 1500) have no candles and must not appear.
        let input = [
            candle(ts: 60,   open: "0.50", high: "0.55", low: "0.48", close: "0.52"),
            candle(ts: 1860, open: "0.60", high: "0.65", low: "0.59", close: "0.63"),
        ]

        let result = CandleAggregation.aggregate(input, bucketMinutes: 5)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].endPeriodTs, 300)
        XCTAssertEqual(result[1].endPeriodTs, 2100) // bucket [1800, 2100)
    }
}
