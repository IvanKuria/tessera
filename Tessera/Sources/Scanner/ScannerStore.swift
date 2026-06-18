import Foundation
import KalshiKit

/// Where a scan pass currently is, for the UI's progress/coverage chrome.
enum ScanPhase: Equatable, Sendable {
    case idle, discovering, detecting, confirming(Int), pricing, degraded(String)
}

/// How much of the market the last pass actually covered — surfaced so the UI
/// can be honest about partial scans (rate limits, book failures).
struct ScanCoverage: Sendable, Equatable {
    var eventsScanned = 0
    var candidates = 0
    var booksFetched = 0
    var booksFailed = 0
}

/// The app-side scanner brain: a `@MainActor @Observable` store that runs a
/// funnel-shaped REST pass — discover → pure-detect → bounded orderbook-confirm
/// → fee/depth-price → publish — on a timer, and projects results into the
/// `locks`/`edges` lanes the UI binds to.
///
/// This slice is **read-only**: no live socket revalue yet (that's Slice 4). The
/// heavy network calls hop to the off-main `actor KalshiClient`; the detection
/// math is pure and runs synchronously on the main actor between awaits.
@MainActor @Observable
final class ScannerStore {
    private(set) var locks: [Opportunity] = []
    private(set) var edges: [Opportunity] = []
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var phase: ScanPhase = .idle
    private(set) var coverage = ScanCoverage()
    private(set) var lastError: String?
    /// Live socket state, surfaced so the UI can show a Live / Reconnecting / Offline badge.
    private(set) var connection: SocketConnectionState = .disconnected
    var settings: ScannerSettings

    private let account: AccountStore
    private let scanClient = KalshiClient(environment: .production)
    private var scanLoop: Task<Void, Never>?
    var oppsByID: [String: Opportunity] = [:]

    // MARK: - Stickiness + alerts (Slice 6)

    /// Edge-triggered, de-duplicated notifier (Task 18).
    private let notifier = ScannerNotifier()
    /// Opportunities the user explicitly tapped "Track & alert me" on (Task 19).
    let tracked = TrackedStore()

    // MARK: - Live revalue infra (Slice 4)

    /// The market-data socket for the current watch set; rebuilt only when the
    /// watch set actually changes (see `restartFeed`).
    private var socket: KalshiSocket?
    private var consumeTask: Task<Void, Never>?
    /// Periodic freshness/auto-expiry sweep (Task 14).
    private var expiryTimer: Task<Void, Never>?

    /// The priced snapshot (WITH fetched books) that produced each surfaced
    /// event's opportunities — keyed by event ticker. The live revalue rebuilds
    /// from these so it keeps the last REST depth ladders.
    private var surfacedEvents: [String: EventSnapshot] = [:]
    /// market ticker → the set of event tickers whose snapshots reference it, so
    /// a ticker update can find which events to re-price.
    private var marketToEvents: [String: Set<String>] = [:]
    /// The last watch set we (re)built the socket for — sorted leg tickers. Used
    /// to avoid thrashing the socket on every 45s pass when nothing changed.
    private var lastWatchSet: [String] = []

    init(account: AccountStore) {
        self.account = account
        self.settings = AppGroup.read(ScannerSettings.self, from: AppGroup.scannerSettingsURL) ?? .default
    }

    // MARK: - Lifecycle

    func start() {
        guard scanLoop == nil else { return }
        // Request notification permission once, like AlertEngine.
        Task { [notifier] in await notifier.requestAuthorizationIfNeeded() }
        scanLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runScanPass()
                let secs = self?.settings.scanIntervalSeconds ?? 45
                try? await Task.sleep(for: .seconds(secs))
            }
        }
        startExpiryTimer()
    }

    func stop() {
        scanLoop?.cancel()
        scanLoop = nil
        consumeTask?.cancel(); consumeTask = nil
        expiryTimer?.cancel(); expiryTimer = nil
        Task { [socket] in await socket?.disconnect() }
        socket = nil
        lastWatchSet = []
        connection = .disconnected
    }

    func refreshNow() { Task { await runScanPass() } }

    func updateSettings(_ s: ScannerSettings) {
        settings = s
        _ = AppGroup.write(s, to: AppGroup.scannerSettingsURL)
    }

    // MARK: - Scan funnel

    private func runScanPass() async {
        guard !isScanning else { return }
        isScanning = true
        phase = .discovering
        defer { isScanning = false; phase = .idle }
        let cfg = makeConfig()
        do {
            // Stage 1: discover open events (capped).
            var events: [Event] = []
            var cursor: String?
            repeat {
                let resp = try await scanClient.events(
                    status: "open", seriesTicker: nil, withNestedMarkets: true, limit: 200, cursor: cursor
                )
                events.append(contentsOf: resp.events)
                cursor = resp.nextCursor
            } while cursor != nil && events.count < settings.maxEventsScanned
            coverage.eventsScanned = events.count

            // Stage 2/3: quote-only snapshots + cheap pure detect to find candidates.
            let now = Date()
            let quoteSnaps = ScanShaping.eventSnapshots(from: events, books: [:], now: now)
            phase = .detecting
            let candidates = DetectionEngine.scan(ScanSnapshot(events: quoteSnaps, now: now, config: cfg))
            // Only Locks and Ladders need depth-aware confirmation — they're the
            // expensive-but-rare candidates. Flag-only Spread/Stale edges are derived
            // from quotes alone and must NOT drag thousands of illiquid markets into
            // the orderbook fan-out (that's what blew the funnel up).
            // Take the most promising candidates first (best quote-pass net edge) and
            // collect their markets until we hit a HARD cap on books-per-pass. This
            // guarantees a pass always completes quickly and never melts the API,
            // regardless of how noisy detection is on a given snapshot.
            let confirmable = candidates
                .filter { needsBookConfirm($0.kind) }
                .sorted { $0.netEdgeCents > $1.netEdgeCents }
            var candidateTickers = Set<String>()
            for c in confirmable {
                if candidateTickers.count >= Self.maxConfirmTickers { break }
                candidateTickers.formUnion(c.legs.map(\.marketTicker))
            }
            coverage.candidates = confirmable.count

            // Stage 4: confirm — fetch real books only for candidate markets, bounded.
            phase = .confirming(candidateTickers.count)
            let books = await fetchBooks(Array(candidateTickers))
            coverage.booksFetched = books.count
            coverage.booksFailed = candidateTickers.count - books.count

            // Stage 5: re-detect with real depth.
            phase = .pricing
            let pricedSnaps = ScanShaping.eventSnapshots(from: events, books: books, now: now)
            let priced = DetectionEngine.scan(ScanSnapshot(events: pricedSnaps, now: now, config: cfg))

            // Stage 6: publish + (re)wire the live feed to the new watch set.
            publish(priced, snaps: pricedSnaps, now: now)
            restartFeed()
            lastScan = now
            lastError = nil
            if coverage.booksFailed > 0 { phase = .degraded("\(coverage.booksFailed) books unavailable") }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Bounded-concurrency orderbook fan-out: keep at most `cap` fetches in flight,
    /// adding one fresh task as each result lands. Index-based loop (not an
    /// `inout`-captured `pump`) to keep Swift 6 strict concurrency happy.
    private func fetchBooks(_ tickers: [String]) async -> [String: Orderbook] {
        let cap = max(1, settings.maxConcurrentBookFetches)
        let depth = settings.bookDepth
        let client = scanClient
        return await withTaskGroup(of: (String, Orderbook?).self) { group in
            var next = 0
            // Prime up to `cap` tasks.
            while next < tickers.count, next < cap {
                let t = tickers[next]
                group.addTask { (t, try? await client.orderbook(ticker: t, depth: depth)) }
                next += 1
            }
            var out: [String: Orderbook] = [:]
            for await (t, book) in group {
                if let book { out[t] = book }
                if next < tickers.count {
                    let nt = tickers[next]
                    group.addTask { (nt, try? await client.orderbook(ticker: nt, depth: depth)) }
                    next += 1
                }
            }
            return out
        }
    }

    private func publish(_ priced: [Opportunity], snaps: [EventSnapshot], now: Date) {
        var next: [String: Opportunity] = [:]
        for var o in priced {
            o.freshnessAgeSeconds = now.timeIntervalSince(o.freshnessTimestamp)
            next[o.id] = o
        }
        oppsByID = next

        // Rebuild the live-revalue caches from the priced snapshots that actually
        // produced surfaced opportunities. Only those events ever receive ticker
        // updates, so we don't cache the whole market.
        let surfacedTickers = Set(priced.map(\.eventTicker))
        var events: [String: EventSnapshot] = [:]
        var marketIndex: [String: Set<String>] = [:]
        for snap in snaps where surfacedTickers.contains(snap.eventTicker) {
            events[snap.eventTicker] = snap
            for m in snap.markets {
                marketIndex[m.ticker, default: []].insert(snap.eventTicker)
            }
        }
        surfacedEvents = events
        marketToEvents = marketIndex

        reproject()
        notifyFreshCrossings()
    }

    /// Fires edge-triggered notifications for every live opportunity, then prunes
    /// the notifier's bookkeeping for ids that have left the scan. Cheap: a single
    /// pass over `oppsByID` with O(1) work per opp. Called after a REST publish and
    /// after a live ticker revalue — the two paths where net edge actually moves.
    private func notifyFreshCrossings() {
        let now = Date()
        let trackedIDs = tracked.ids
        for opp in oppsByID.values {
            notifier.consider(opp, settings: settings, tracked: trackedIDs, now: now)
        }
        notifier.prune(keeping: Set(oppsByID.keys))
    }

    /// Projects `oppsByID` into the `locks`/`edges` lanes the UI binds to. Shared
    /// by the REST publish path and the live ticker-revalue path so both apply the
    /// same ranking + flag-edge cap.
    private func reproject() {
        let cfg = makeConfig()
        let all = DetectionEngine.ranked(Array(oppsByID.values), config: cfg)
        locks = settings.locksEnabled ? all.filter { $0.lane == .lock } : []

        // Edges lane: real ladder edges first (depth-priced), then only the
        // strongest flag-only signals — never a wall of thousands of wide-spread
        // illiquid markets, which would bury the actionable rows.
        let allEdges = all.filter { $0.lane == .edge }
        let ladderEdges = allEdges.filter { needsBookConfirm($0.kind) }
        let flagEdges = allEdges.filter { !needsBookConfirm($0.kind) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(Self.maxFlagEdges)
        edges = settings.edgesEnabled ? ladderEdges + Array(flagEdges) : []
    }

    // MARK: - Live revalue (Task 13)

    /// Distinct leg tickers across all currently-surfaced opportunities — the set
    /// of markets we need live ticker updates for.
    private var watchedMarkets: [String] {
        var set = Set<String>()
        for o in oppsByID.values { for l in o.legs { set.insert(l.marketTicker) } }
        return set.sorted()
    }

    /// Tears down and rebuilds the socket for the current watch set — but ONLY when
    /// the watch set actually changed, so a 45s pass that surfaces the same markets
    /// doesn't thrash the connection. Adapted from `AlertEngine.restartFeed`.
    private func restartFeed() {
        let markets = watchedMarkets
        guard markets != lastWatchSet else { return }
        lastWatchSet = markets

        consumeTask?.cancel()
        let old = socket
        socket = nil
        Task { await old?.disconnect() }

        guard !markets.isEmpty else { connection = .disconnected; return }

        var channels: [SocketChannel] = [.ticker]
        if settings.useOrderbookDelta { channels.append(.orderbookDelta) }

        let sock = KalshiSocket(environment: account.kalshiEnvironment, signer: account.liveSigner)
        socket = sock
        connection = .connecting
        consumeTask = Task { [weak self] in
            let events = await sock.events()
            await sock.connect()
            await sock.subscribe(to: channels, markets: markets)
            for await event in events {
                guard let self else { break }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: SocketEvent) {
        switch event {
        case .connected:
            connection = .connected
        case .disconnected:
            // Do NOT expire opps on disconnect — the REST snapshot stays valid.
            connection = .disconnected
        case .ticker(let t):
            applyTicker(t)
        default:
            break
        }
    }

    /// Re-prices the events that reference a just-ticked market off the cached
    /// REST snapshots (keeping their depth ladders), reconciles the result into
    /// `oppsByID`, and re-projects the lanes.
    private func applyTicker(_ t: TickerUpdate) {
        guard let ticker = t.marketTicker else { return }
        guard let eventTickers = marketToEvents[ticker], !eventTickers.isEmpty else { return }

        let now = Date()
        var changed = false
        for eventTicker in eventTickers {
            guard let snap = surfacedEvents[eventTicker] else { continue }
            guard let idx = snap.markets.firstIndex(where: { $0.ticker == ticker }) else { continue }

            // Build an updated MarketSnapshot: prefer explicit yes bid/ask from the
            // payload; otherwise nudge both quotes toward the new last price so a
            // last-only tick still moves the valuation. Keep the last REST ladders.
            let old = snap.markets[idx]
            let newAsk = t.yesAsk ?? centsOf(t.yesAskDollars) ?? t.lastCents ?? old.bestYesAskCents
            let newBid = t.yesBid ?? centsOf(t.yesBidDollars) ?? t.lastCents ?? old.bestYesBidCents
            let updatedMarket = MarketSnapshot(
                ticker: old.ticker,
                seriesTicker: old.seriesTicker,
                bestYesAskCents: newAsk,
                bestYesBidCents: newBid,
                yesAskLadder: old.yesAskLadder,
                noAskLadder: old.noAskLadder,
                strike: old.strike,
                expiration: old.expiration,
                lastUpdate: now
            )
            var markets = snap.markets
            markets[idx] = updatedMarket
            let updatedEvent = EventSnapshot(
                eventTicker: snap.eventTicker,
                seriesTicker: snap.seriesTicker,
                title: snap.title,
                category: snap.category,
                mutuallyExclusive: snap.mutuallyExclusive,
                markets: markets
            )
            surfacedEvents[eventTicker] = updatedEvent

            // Re-detect just this event with the refreshed quote.
            let repriced = DetectionEngine.scan(
                ScanSnapshot(events: [updatedEvent], now: now, config: makeConfig())
            )

            // Reconcile: update surviving opps in place (live + fresh); drop opps
            // from this event that detection no longer returns (their edge died).
            let repricedByID = Dictionary(uniqueKeysWithValues: repriced.map { ($0.id, $0) })
            let previousIDs = oppsByID.values
                .filter { $0.eventTicker == eventTicker }
                .map(\.id)
            for var o in repriced {
                o.isLive = true
                o.freshnessTimestamp = now
                o.freshnessAgeSeconds = 0
                oppsByID[o.id] = o
                changed = true
            }
            for id in previousIDs where repricedByID[id] == nil {
                oppsByID.removeValue(forKey: id)
                changed = true
            }
        }

        guard changed else { return }
        reproject()
        notifyFreshCrossings()
        // The watch set may have shrunk (an edge died). Re-wire if so.
        restartFeed()
    }

    /// `KalshiDecimal` dollars → integer cents (Decimal half-up, no Double error).
    private func centsOf(_ d: KalshiDecimal?) -> Int? { d?.centsRounded }

    // MARK: - Freshness + auto-expiry (Task 14)

    private func startExpiryTimer() {
        guard expiryTimer == nil else { return }
        expiryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await self?.sweepFreshness()
            }
        }
    }

    /// Ages every opportunity, drops live status after silence, and expires stale
    /// REST-only rows — but NEVER while disconnected, since then the REST snapshot
    /// is the only floor we have and must stay valid.
    private func sweepFreshness() {
        guard !oppsByID.isEmpty else { return }
        let now = Date()
        let silence = Double(settings.maxLiveSilenceSeconds)
        let stale = Double(settings.maxStaleSeconds)
        let offline = connection == .disconnected

        var changed = false
        for (id, var o) in oppsByID {
            let age = now.timeIntervalSince(o.freshnessTimestamp)
            if o.freshnessAgeSeconds != age { o.freshnessAgeSeconds = age; changed = true }
            if o.isLive && age > silence { o.isLive = false; changed = true }
            oppsByID[id] = o
            // Expire only when we have a live feed; offline keeps the REST floor.
            if !offline && !o.isLive && age > stale {
                oppsByID.removeValue(forKey: id)
                changed = true
            }
        }
        if changed {
            reproject()
            restartFeed()
        }
    }

    /// Lock + ladder opportunities need real orderbook depth to price net edge;
    /// spread/stale flags are quote-only signals.
    private func needsBookConfirm(_ kind: OpportunityKind) -> Bool {
        switch kind {
        case .lock: return true
        case .edge(.ladderMonotonicity): return true
        case .edge(.wideSpread), .edge(.staleQuote): return false
        }
    }

    // MARK: - Daily digest (Task 20)

    /// The day's best mispricings: top Locks by net edge + top Edges by confidence,
    /// each carrying how long it has survived (freshness age). Honest, no hype.
    func buildDigest(now: Date = Date()) -> ScannerDigest {
        let live = Array(oppsByID.values)
        let topLocks = live
            .filter { $0.lane == .lock }
            .sorted { $0.netEdgeCents > $1.netEdgeCents }
            .prefix(5)
            .map { DigestItem(opp: $0, now: now) }
        let topEdges = live
            .filter { $0.lane == .edge && !$0.isFlagOnly }
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { DigestItem(opp: $0, now: now) }
        return ScannerDigest(generatedAt: now, locks: Array(topLocks), edges: Array(topEdges))
    }

    /// Fires at most ONE digest notification per calendar day (cadence cap via a
    /// stored last-digest date). Returns the digest it built so the UI can show it.
    @discardableResult
    func sendDigestIfDue(now: Date = Date()) -> ScannerDigest {
        let digest = buildDigest(now: now)
        guard settings.digestEnabled else { return digest }
        let last = AppGroup.read(Date.self, from: AppGroup.scannerDigestURL)
        if let last, Calendar.current.isDate(last, inSameDayAs: now) {
            return digest // already sent today
        }
        Task { [notifier] in await notifier.requestAuthorizationIfNeeded() }
        digest.postNotification()
        AppGroup.write(now, to: AppGroup.scannerDigestURL)
        return digest
    }

    /// Generates today's digest on demand (the "Generate today's digest" button)
    /// WITHOUT touching the daily cadence cap — manual previews never count.
    func previewDigest(now: Date = Date()) -> ScannerDigest { buildDigest(now: now) }

    private static let maxFlagEdges = 25
    /// Hard ceiling on orderbooks confirmed per pass — bounds cost + latency so a
    /// scan always finishes in seconds even when detection is noisy.
    private static let maxConfirmTickers = 120

    private func makeConfig() -> DetectorConfig {
        DetectorConfig(
            maxStakeContracts: 100,
            minNetEdgeCents: Decimal(settings.minNetEdgeCents),
            wideSpreadCents: settings.minSpreadCents
        )
    }
}
