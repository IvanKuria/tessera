import Foundation

/// Pure, CLI-testable helpers for synthesizing coarser candlestick intervals
/// from finer native ones.
///
/// Kalshi's candlestick API only emits three native `period_interval`s — 1
/// minute, 1 hour (60), and 1 day (1440). Charts that want intermediate
/// resolutions (e.g. 5m, 15m, 4h) must aggregate finer candles client-side.
/// ``CandleAggregation`` provides that as a side-effect-free function so the
/// behaviour is unit-testable without touching the network.
public enum CandleAggregation {

    /// Aggregate fine-grained candles into coarser fixed-size buckets.
    ///
    /// Candles are grouped by flooring each candle's ``Candlestick/endPeriodTs``
    /// to a `bucketMinutes * 60` second boundary. Each produced bucket carries:
    /// - **open** = first candle's open in the bucket,
    /// - **high** = max high across the bucket,
    /// - **low**  = min low across the bucket,
    /// - **close** = last candle's close in the bucket,
    /// - **volume** (`volumeFp`) and **open interest** (`openInterestFp`) = sum.
    ///
    /// OHLC are aggregated independently for each of the trade ``Candlestick/price``,
    /// ``Candlestick/yesBid`` and ``Candlestick/yesAsk`` series, so the
    /// ``Candlestick/probability`` fallback keeps working on the result.
    ///
    /// The aggregated candle's `endPeriodTs` is set to the **end** of its bucket
    /// (`bucketStart + bucketMinutes * 60`), matching the API convention that the
    /// timestamp marks the end of the period.
    ///
    /// Edge cases:
    /// - Empty input returns an empty array.
    /// - A `bucketMinutes` smaller than or equal to the source spacing degrades to
    ///   a passthrough grouping (each candle lands in its own bucket).
    /// - Gaps produce no bucket — empty buckets are never synthesized.
    /// - Candles with a `nil` `endPeriodTs` are skipped (they cannot be bucketed).
    ///
    /// - Parameters:
    ///   - candles: Fine-grained candles, assumed sorted ascending by time.
    ///   - bucketMinutes: Target bucket size in minutes. Values `<= 0` are
    ///     treated as a passthrough (no aggregation), returning `candles` as-is.
    /// - Returns: Aggregated candles, one per non-empty bucket, sorted ascending.
    public static func aggregate(
        _ candles: [Candlestick],
        bucketMinutes: Int
    ) -> [Candlestick] {
        guard bucketMinutes > 0 else { return candles }
        guard !candles.isEmpty else { return [] }

        let bucketSeconds = bucketMinutes * 60

        // Group by floored bucket start, preserving input order within a bucket.
        var order: [Int] = []
        var groups: [Int: [Candlestick]] = [:]
        for candle in candles {
            guard let ts = candle.endPeriodTs else { continue }
            let bucketStart = Int((Double(ts) / Double(bucketSeconds)).rounded(.down)) * bucketSeconds
            if groups[bucketStart] == nil {
                groups[bucketStart] = []
                order.append(bucketStart)
            }
            groups[bucketStart]?.append(candle)
        }

        return order.sorted().compactMap { bucketStart in
            guard let bucket = groups[bucketStart], !bucket.isEmpty else { return nil }
            return reduce(bucket, bucketEndTs: bucketStart + bucketSeconds)
        }
    }

    /// Collapse one non-empty bucket of candles into a single candle.
    private static func reduce(_ bucket: [Candlestick], bucketEndTs: Int) -> Candlestick {
        Candlestick(
            endPeriodTs: bucketEndTs,
            openInterestFp: sum(bucket.map(\.openInterestFp)),
            volumeFp: sum(bucket.map(\.volumeFp)),
            price: reduceOHLC(bucket.map(\.price)),
            yesBid: reduceOHLC(bucket.map(\.yesBid)),
            yesAsk: reduceOHLC(bucket.map(\.yesAsk))
        )
    }

    /// Aggregate one OHLC series across a bucket (open=first, high=max, low=min,
    /// close=last). Returns `nil` if no candle in the bucket carries that series.
    private static func reduceOHLC(_ series: [Candlestick.OHLC?]) -> Candlestick.OHLC? {
        let present = series.compactMap { $0 }
        guard !present.isEmpty else { return nil }

        let open = present.first(where: { $0.openDollars != nil })?.openDollars
        let close = present.last(where: { $0.closeDollars != nil })?.closeDollars
        let high = present.compactMap(\.highDollars).max()
        let low = present.compactMap(\.lowDollars).min()

        return Candlestick.OHLC(
            openDollars: open,
            highDollars: high,
            lowDollars: low,
            closeDollars: close
        )
    }

    /// Sum a column of optional decimals. Returns `nil` only when every value is
    /// absent; otherwise present values are summed.
    private static func sum(_ values: [KalshiDecimal?]) -> KalshiDecimal? {
        let present = values.compactMap { $0?.value }
        guard !present.isEmpty else { return nil }
        return KalshiDecimal(present.reduce(Decimal(0), +))
    }
}
