import Foundation
import KalshiKit
import PolymarketKit
import ArbEngine

/// Where a cross-venue scan pass currently is, for the UI's progress chrome.
enum ArbScanPhase: Equatable, Sendable {
    case idle, discovering, matching, confirming(Int), detecting, degraded(String)
}

/// How much of the two venues the last pass actually covered — surfaced so the
/// UI stays honest about partial scans (rate limits, book failures, caps hit).
struct ArbCoverage: Sendable, Equatable {
    var kalshiMarkets = 0
    var polymarketMarkets = 0
    var matchedPairs = 0
    var pairsConfirmed = 0
    var booksFailed = 0
}

/// User-tunable knobs for the cross-venue arbitrage scanner. Pure value type.
struct ArbSettings: Sendable, Equatable {
    var scanIntervalSeconds: Int = 90
    /// Cap on Kalshi binary markets pulled into the match (cost control).
    var maxKalshiMarkets: Int = 1_200
    /// Cap on Polymarket open markets pulled into the match (cost control).
    var maxPolymarketMarkets: Int = 2_400 // Gamma offset-paginates up to ~2.4k (422 beyond)
    /// HARD cap on matched pairs we confirm books for per pass (the expensive,
    /// rare step — the Scanner's `maxConfirmTickers` lesson, scaled for 3 book
    /// fetches per pair across two venues).
    var maxConfirmPairs: Int = 40
    /// Bounded fan-out: at most this many venues' books fetched concurrently.
    var maxConcurrentFetches: Int = 6
    /// Minimum match confidence (0…1) for a pair to be confirmed.
    // Conservative: a simple title-embedding matcher gives ~0.47 to coincidental
    // token overlap, so anything below this is noise. Genuine high-overlap pairs
    // score higher. Better honestly empty than showing false "arbitrage".
    var minConfidence: Decimal = Decimal(string: "0.55")!
    /// Minimum net-of-fee edge per contract (cents) for an opportunity to surface.
    var minNetEdgeCents: Int = 1
    /// Max displayed rows.
    var maxDisplayedRows: Int = 60
    static let `default` = ArbSettings()
}

/// The app-side cross-venue arbitrage brain: a `@MainActor @Observable` store
/// that runs a funnel-shaped, read-only REST pass —
/// **discover** (Kalshi events + Polymarket Gamma markets) → **match**
/// (`EventMatcher`) → **confirm** (bounded fan-out of Kalshi + PM order books) →
/// **detect** (`CrossVenueArbDetector`) → **publish/rank/freshness** — on a timer.
///
/// Mirrors `ScannerStore`'s shape so the UI binds the same way, but there is one
/// lane (cross-venue) and NO order placement: opportunities deep-link to each
/// venue. The heavy network calls hop off-main to the `actor KalshiClient` and
/// the PolymarketKit `actor PMClient`; the matcher and detector are pure.
@MainActor @Observable
final class ArbStore {
    private(set) var opportunities: [Opportunity] = []
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var phase: ArbScanPhase = .idle
    private(set) var coverage = ArbCoverage()
    private(set) var lastError: String?
    /// Cross-venue arb is REST-polled, not socket-revalued; surfaced so the UI
    /// can render the same liveness chrome as the Scanner (always `.disconnected`).
    private(set) var connection: SocketConnectionState = .disconnected
    var settings: ArbSettings

    /// Side map: opportunity id → the matched pair that produced it. Carries the
    /// resolution texts (for the mismatch banner) and the PM slug (for deep-links).
    private(set) var pairByOppID: [String: MatchedPair] = [:]
    /// PM market id → slug, so a Polymarket leg can deep-link even though the
    /// `Leg` only carries the market id as its ticker.
    private(set) var pmSlugByID: [String: String] = [:]

    private let kalshiClient = KalshiClient(environment: .production)
    private let gamma: GammaService
    private let clob: ClobService
    private var scanLoop: Task<Void, Never>?

    init() {
        let pm = PMClient()
        self.gamma = GammaService(client: pm)
        self.clob = ClobService(client: pm)
        self.settings = .default
    }

    // MARK: - Lifecycle

    func start() {
        guard scanLoop == nil else { return }
        scanLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runScanPass()
                let secs = self?.settings.scanIntervalSeconds ?? 90
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    func stop() {
        scanLoop?.cancel()
        scanLoop = nil
    }

    func refreshNow() { Task { await runScanPass() } }

    // MARK: - Scan funnel

    private func runScanPass() async {
        guard !isScanning else { return }
        isScanning = true
        phase = .discovering
        defer { isScanning = false; phase = .idle }

        let now = Date()
        do {
            // Stage 1: discover — Kalshi open events (nested markets) + Polymarket
            // open Gamma markets. Both keyless, both off-main, both hard-capped.
            async let kalshiRefsTask = discoverKalshi()
            async let pmResultTask = discoverPolymarket()
            let kalshiRefs = try await kalshiRefsTask
            let (pmRefs, slugs) = try await pmResultTask
            coverage.kalshiMarkets = kalshiRefs.count
            coverage.polymarketMarkets = pmRefs.count
            pmSlugByID = slugs

            // Stage 2: match (pure) — only binary pairs ≥ minConfidence.
            phase = .matching
            let matchConfig = MatchConfig(minConfidence: settings.minConfidence)
            var pairs = EventMatcher.match(kalshi: kalshiRefs, polymarket: pmRefs, config: matchConfig)
            coverage.matchedPairs = pairs.count
            // HARD-CAP confirmed pairs per pass (cost): keep the most confident.
            pairs.sort { $0.confidence > $1.confidence }
            if pairs.count > settings.maxConfirmPairs {
                pairs = Array(pairs.prefix(settings.maxConfirmPairs))
            }

            // Stage 3: confirm — fetch the Kalshi + PM books for each pair, bounded.
            phase = .confirming(pairs.count)
            let booksByPairIndex = await fetchBooks(for: pairs)
            coverage.pairsConfirmed = booksByPairIndex.count
            coverage.booksFailed = pairs.count - booksByPairIndex.count

            // Stage 4: detect (pure) — emit Opportunities, dedupe by id.
            phase = .detecting
            let cfg = makeConfig()
            var byID: [String: Opportunity] = [:]
            var pairMap: [String: MatchedPair] = [:]
            for (idx, books) in booksByPairIndex {
                let pair = pairs[idx]
                guard let opp = CrossVenueArbDetector.detect(pair, books: books, config: cfg, now: now) else { continue }
                byID[opp.id] = opp
                pairMap[opp.id] = pair
            }

            // Stage 5: publish — rank by net edge desc, set freshness, cap rows.
            publish(Array(byID.values), pairMap: pairMap, now: now)
            lastScan = now
            lastError = nil
            if coverage.booksFailed > 0 {
                phase = .degraded("\(coverage.booksFailed) book(s) unavailable")
            }
        } catch {
            lastError = String(describing: error)
            phase = .degraded("scan failed")
        }
    }

    // MARK: - Discover

    /// Kalshi open events with nested markets → one `VenueMarketRef` per binary
    /// market. Title comes from the event (the human question); rules text from
    /// the market subtitle. Capped at `maxKalshiMarkets`.
    private func discoverKalshi() async throws -> [VenueMarketRef] {
        var refs: [VenueMarketRef] = []
        var cursor: String?
        let client = kalshiClient
        repeat {
            let resp = try await client.events(
                status: "open", seriesTicker: nil, withNestedMarkets: true, limit: 200, cursor: cursor
            )
            for event in resp.events {
                guard let markets = event.markets else { continue }
                for market in markets where market.status == .active || market.status == .unknown {
                    let rules = [market.yesSubTitle, market.subtitle, event.subTitle]
                        .compactMap { $0 }
                        .first { !$0.isEmpty }
                    // Build a SPECIFIC title for matching: multi-outcome Kalshi
                    // events split into binary markets all share the generic event
                    // question, so fold in this market's own outcome label (e.g.
                    // event "Who will be next AG?" + outcome "Pam Bondi") so it can
                    // align with Polymarket's specific question.
                    let outcomeLabel = (market.yesSubTitle ?? market.subtitle ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    let isGeneric = outcomeLabel.isEmpty
                        || outcomeLabel.caseInsensitiveCompare("Yes") == .orderedSame
                    let matchTitle = isGeneric ? event.title : "\(event.title) \(outcomeLabel)"
                    refs.append(VenueMarketRef(
                        id: market.ticker,
                        title: matchTitle,
                        category: event.category,
                        closeDate: market.closeDate,
                        outcomes: ["Yes", "No"],
                        resolutionText: rules
                    ))
                    if refs.count >= settings.maxKalshiMarkets { return refs }
                }
            }
            cursor = resp.nextCursor
        } while cursor != nil && refs.count < settings.maxKalshiMarkets
        return refs
    }

    /// Polymarket open Gamma markets → `VenueMarketRef`(polymarket:) plus an
    /// id→slug map for deep-linking. Capped at `maxPolymarketMarkets`.
    private func discoverPolymarket() async throws -> ([VenueMarketRef], [String: String]) {
        // Gamma caps `limit` at 100 server-side, so page size is 100 regardless.
        let pageLimit = 100
        let maxPages = max(1, (settings.maxPolymarketMarkets + pageLimit - 1) / pageLimit)
        let markets = try await gamma.allOpenMarkets(pageLimit: pageLimit, maxPages: maxPages)
        var refs: [VenueMarketRef] = []
        var slugs: [String: String] = [:]
        for m in markets.prefix(settings.maxPolymarketMarkets) {
            refs.append(VenueMarketRef(polymarket: m))
            slugs[m.id] = m.slug
        }
        return (refs, slugs)
    }

    // MARK: - Confirm (bounded fan-out)

    /// For each matched pair, fetch the Kalshi orderbook + the PM CLOB books for
    /// the YES and NO tokens and assemble `VenueBooks`. Bounded-concurrency over
    /// PAIRS (each pair = 3 network calls): at most `cap` pairs in flight, a new
    /// one started as each result lands. `try?`-tolerant — a pair whose books
    /// can't all be fetched is simply dropped from the result.
    private func fetchBooks(for pairs: [MatchedPair]) async -> [(Int, VenueBooks)] {
        let cap = max(1, settings.maxConcurrentFetches)
        let kc = kalshiClient
        let cl = clob
        return await withTaskGroup(of: (Int, VenueBooks?).self) { group in
            var next = 0
            func addTask(_ idx: Int) {
                let pair = pairs[idx]
                group.addTask {
                    async let kBook = try? await kc.orderbook(ticker: pair.kalshi.id, depth: 10)
                    async let yesBook = try? await cl.book(tokenID: pair.pmYesTokenID)
                    async let noBook = try? await cl.book(tokenID: pair.pmNoTokenID)
                    guard let k = await kBook, let y = await yesBook, let n = await noBook else {
                        return (idx, nil)
                    }
                    return (idx, Ladder.venueBooks(kalshi: k, pmYes: y, pmNo: n))
                }
            }
            while next < pairs.count, next < cap { addTask(next); next += 1 }
            var out: [(Int, VenueBooks)] = []
            for await (idx, books) in group {
                if let books { out.append((idx, books)) }
                if next < pairs.count { addTask(next); next += 1 }
            }
            return out
        }
    }

    // MARK: - Publish

    private func publish(_ priced: [Opportunity], pairMap: [String: MatchedPair], now: Date) {
        let ranked = priced
            .map { o -> Opportunity in
                var o = o
                o.freshnessAgeSeconds = now.timeIntervalSince(o.freshnessTimestamp)
                return o
            }
            .sorted { $0.netEdgeCents > $1.netEdgeCents }
        opportunities = Array(ranked.prefix(settings.maxDisplayedRows))
        pairByOppID = pairMap
    }

    /// Look up the matched pair behind an opportunity (resolution texts + slug).
    func pair(for opp: Opportunity) -> MatchedPair? { pairByOppID[opp.id] }

    /// The Polymarket deep-link slug for an opportunity's PM leg, if known.
    func polymarketSlug(for opp: Opportunity) -> String? {
        guard let pair = pairByOppID[opp.id] else { return nil }
        return pmSlugByID[pair.polymarket.id]
    }

    private func makeConfig() -> DetectorConfig {
        DetectorConfig(
            maxStakeContracts: 100,
            minNetEdgeCents: Decimal(settings.minNetEdgeCents)
        )
    }
}
