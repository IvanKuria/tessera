import Foundation
import KalshiKit

/// Pure bridge from KalshiKit's wire types (`Event`/`Market`/`Orderbook`) to the
/// detection engine's value-type inputs (`EventSnapshot`/`MarketSnapshot`).
///
/// Two-pass funnel friendly: with an empty `books` map this yields *quote-only*
/// snapshots (best YES ask/bid + a single optimistic ladder rung) good enough to
/// flag candidates cheaply; once real L2 books are fetched for the candidates it
/// fills in the true ladders for fee/depth-accurate pricing.
enum ScanShaping {
    static func eventSnapshots(from events: [Event], books: [String: Orderbook], now: Date) -> [EventSnapshot] {
        events.compactMap { e in
            let markets = (e.markets ?? []).filter { $0.status.isOpen }.map { m -> MarketSnapshot in
                let book = books[m.ticker]
                let yesLadder = book?.yesAskLevels.map { (price: $0.priceCents, size: $0.size) } ?? []
                // `noBidLevels` are NO-bid prices; the NO-ask ladder (buying NO) is 100 − each.
                let noLadder = book?.noBidLevels.map { (price: 100 - $0.priceCents, size: $0.size) } ?? []
                let yesAsk = centsOf(m.yesAskDollars) ?? m.yesAsk
                let yesBid = centsOf(m.yesBidDollars) ?? m.yesBid
                return MarketSnapshot(
                    ticker: m.ticker,
                    seriesTicker: e.seriesTicker,
                    bestYesAskCents: yesAsk,
                    bestYesBidCents: yesBid,
                    yesAskLadder: yesLadder.isEmpty ? quoteLadder(yesAsk) : yesLadder,
                    noAskLadder: noLadder.isEmpty ? quoteLadder(yesBid.map { 100 - $0 }) : noLadder,
                    strike: parseStrike(m),
                    expiration: m.latestExpirationDate ?? m.closeDate,
                    lastUpdate: now
                )
            }
            guard !markets.isEmpty else { return nil }
            return EventSnapshot(
                eventTicker: e.eventTicker,
                seriesTicker: e.seriesTicker,
                title: e.title,
                category: e.category,
                mutuallyExclusive: e.mutuallyExclusive ?? false,
                markets: markets
            )
        }
    }

    /// Convert a `KalshiDecimal` dollar value to integer cents using the SDK's
    /// `centsRounded` helper (Decimal math, half-up — no Double error).
    private static func centsOf(_ d: KalshiDecimal?) -> Int? { d?.centsRounded }

    /// Optimistic single-rung placeholder ladder for quote-only (pre-book) passes.
    /// Replaced by the real L2 book at the Confirm stage.
    private static func quoteLadder(_ price: Int?) -> [(price: Int, size: Decimal)] {
        guard let price, (1...99).contains(price) else { return [] }
        return [(price, Decimal(1000))]
    }

    /// Heuristic strike parse from a Kalshi cap/floor ticker tail (e.g. `…-T75`,
    /// `…-B6000`): take the trailing number after the last `-`, dropping the
    /// leading T/B letter. Unparseable tickers yield `nil` (no ladder edge).
    static func parseStrike(_ market: Market) -> Double? {
        let t = market.ticker
        guard let dash = t.lastIndex(of: "-") else { return nil }
        let tail = t[t.index(after: dash)...].dropFirst()
        return Double(tail)
    }
}
