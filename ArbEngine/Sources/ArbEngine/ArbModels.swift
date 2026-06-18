import Foundation
import KalshiKit
import PolymarketKit

// MARK: - VenueMarketRef

/// A distilled, venue-agnostic description of one binary market, used as the
/// input to ``EventMatcher``. Deliberately independent of the KalshiKit /
/// PolymarketKit wire types so tests (and the app's adapter layer) can build
/// these by hand. Polymarket refs additionally carry their CLOB token ids so a
/// matched pair can later fetch the correct order books.
public struct VenueMarketRef: Sendable, Hashable, Identifiable {
    /// Stable identifier on the originating venue (Kalshi ticker, PM market id).
    public let id: String
    /// The human-readable market question/title.
    public let title: String
    /// Best-effort category bucket, if known.
    public let category: String?
    /// When the market closes / resolves, if known.
    public let closeDate: Date?
    /// Outcome labels (binary markets are ≈ `["Yes", "No"]`).
    public let outcomes: [String]
    /// Resolution criteria / rules text, if present.
    public let resolutionText: String?
    /// Polymarket YES-outcome CLOB token id (nil for Kalshi refs).
    public let pmYesTokenID: String?
    /// Polymarket NO-outcome CLOB token id (nil for Kalshi refs).
    public let pmNoTokenID: String?

    public init(
        id: String,
        title: String,
        category: String? = nil,
        closeDate: Date? = nil,
        outcomes: [String] = ["Yes", "No"],
        resolutionText: String? = nil,
        pmYesTokenID: String? = nil,
        pmNoTokenID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.closeDate = closeDate
        self.outcomes = outcomes
        self.resolutionText = resolutionText
        self.pmYesTokenID = pmYesTokenID
        self.pmNoTokenID = pmNoTokenID
    }

    /// Whether the market is binary (two outcomes resembling Yes/No).
    public var isBinary: Bool {
        guard outcomes.count == 2 else { return false }
        let normalized = Set(outcomes.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        return normalized == ["yes", "no"]
    }
}

// MARK: - VenueMarketRef from PMMarket

extension VenueMarketRef {
    /// Builds a Polymarket ``VenueMarketRef`` from a Gamma ``PMMarket``,
    /// carrying its CLOB token ids (outcome-aligned with ``PMMarket/outcomes``).
    public init(polymarket m: PMMarket) {
        // Align YES/NO token ids to the outcome labels when possible; default to
        // positional order (index 0 = YES, 1 = NO) which Gamma uses for binaries.
        var yesToken: String?
        var noToken: String?
        for (i, label) in m.outcomes.enumerated() where i < m.clobTokenIds.count {
            switch label.lowercased().trimmingCharacters(in: .whitespaces) {
            case "yes": yesToken = m.clobTokenIds[i]
            case "no": noToken = m.clobTokenIds[i]
            default: break
            }
        }
        if yesToken == nil, m.clobTokenIds.count >= 1 { yesToken = m.clobTokenIds[0] }
        if noToken == nil, m.clobTokenIds.count >= 2 { noToken = m.clobTokenIds[1] }

        self.init(
            id: m.id,
            title: m.question,
            category: m.category,
            closeDate: m.endDate,
            outcomes: m.outcomes,
            resolutionText: m.description,
            pmYesTokenID: yesToken,
            pmNoTokenID: noToken
        )
    }
}

// MARK: - MatchedPair

/// A Kalshi market matched to a Polymarket market by ``EventMatcher``, with the
/// PM token ids needed to fetch books and the matcher's confidence / mismatch
/// verdict carried through to the detector.
public struct MatchedPair: Sendable, Hashable {
    public let kalshi: VenueMarketRef
    public let polymarket: VenueMarketRef
    public let pmYesTokenID: String
    public let pmNoTokenID: String
    public let confidence: Decimal
    public let resolutionMismatch: Bool
    public let kalshiRules: String?
    public let pmResolution: String?

    public init(
        kalshi: VenueMarketRef,
        polymarket: VenueMarketRef,
        pmYesTokenID: String,
        pmNoTokenID: String,
        confidence: Decimal,
        resolutionMismatch: Bool,
        kalshiRules: String? = nil,
        pmResolution: String? = nil
    ) {
        self.kalshi = kalshi
        self.polymarket = polymarket
        self.pmYesTokenID = pmYesTokenID
        self.pmNoTokenID = pmNoTokenID
        self.confidence = confidence
        self.resolutionMismatch = resolutionMismatch
        self.kalshiRules = kalshiRules
        self.pmResolution = pmResolution
    }
}

// MARK: - VenueBooks

/// The four ascending integer-cent ask ladders the cross-venue detector walks.
/// PM prices (0…1) are converted to cents (×100). The "No" ladders come from
/// buying the No side: on Kalshi this is the derived `100 − yesBid` book; on
/// Polymarket it is the ask side of the NO token's book.
public struct VenueBooks: Sendable {
    /// Ascending YES-ask ladder on Kalshi: (priceCents, size).
    public let kalshiYesAsk: [Ladder.Level]
    /// Ascending NO-ask ladder on Kalshi: (priceCents, size).
    public let kalshiNoAsk: [Ladder.Level]
    /// Ascending YES-ask ladder on Polymarket: (priceCents, size).
    public let pmYesAsk: [Ladder.Level]
    /// Ascending NO-ask ladder on Polymarket: (priceCents, size).
    public let pmNoAsk: [Ladder.Level]

    public init(
        kalshiYesAsk: [Ladder.Level],
        kalshiNoAsk: [Ladder.Level],
        pmYesAsk: [Ladder.Level],
        pmNoAsk: [Ladder.Level]
    ) {
        self.kalshiYesAsk = kalshiYesAsk
        self.kalshiNoAsk = kalshiNoAsk
        self.pmYesAsk = pmYesAsk
        self.pmNoAsk = pmNoAsk
    }
}

/// Ladder helpers and the `(price, size)` tuple shape used throughout.
public enum Ladder {
    /// One integer-cent ask level.
    public typealias Level = (price: Int, size: Decimal)

    /// Maps a Polymarket order book's ask side to an ascending integer-cent
    /// ladder. PM ask `price` is a probability in `0…1`; ×100 gives cents.
    /// Levels priced outside `1…99` are dropped (no tradable edge there).
    public static func fromPMAsks(_ book: PMOrderbook) -> [Level] {
        book.asks
            .compactMap { lvl -> Level? in
                let cents = Self.centsFromProbability(lvl.price)
                guard (1...99).contains(cents) else { return nil }
                return (price: cents, size: lvl.size)
            }
            .sorted { $0.price < $1.price }
    }

    /// Builds Kalshi YES/NO ask ladders from a KalshiKit ``Orderbook``.
    /// YES asks come from the derived sell-YES side; NO asks are `100 − yesBid`.
    public static func fromKalshi(_ book: Orderbook) -> (yesAsk: [Level], noAsk: [Level]) {
        var yesAsk: [Level] = []
        for lvl in book.yesAskLevels where (1...99).contains(lvl.priceCents) {
            yesAsk.append((price: lvl.priceCents, size: lvl.size))
        }
        yesAsk.sort { $0.price < $1.price }
        // Buying NO = selling YES at the bid; a NO ask at `100 − p` for each YES bid `p`.
        var noAsk: [Level] = []
        for lvl in book.yesBidLevels {
            let p = 100 - lvl.priceCents
            if (1...99).contains(p) { noAsk.append((price: p, size: lvl.size)) }
        }
        noAsk.sort { $0.price < $1.price }
        return (yesAsk, noAsk)
    }

    /// Convenience: assemble ``VenueBooks`` from a Kalshi book plus the two
    /// Polymarket token books (YES token book, NO token book).
    public static func venueBooks(
        kalshi: Orderbook,
        pmYes: PMOrderbook,
        pmNo: PMOrderbook
    ) -> VenueBooks {
        let k = fromKalshi(kalshi)
        return VenueBooks(
            kalshiYesAsk: k.yesAsk,
            kalshiNoAsk: k.noAsk,
            pmYesAsk: fromPMAsks(pmYes),
            pmNoAsk: fromPMAsks(pmNo)
        )
    }

    /// Rounds a `0…1` probability to whole cents.
    static func centsFromProbability(_ p: Decimal) -> Int {
        var scaled = p * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
