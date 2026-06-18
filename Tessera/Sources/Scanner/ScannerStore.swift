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
    var settings: ScannerSettings

    private let account: AccountStore
    private let scanClient = KalshiClient(environment: .production)
    private var scanLoop: Task<Void, Never>?
    var oppsByID: [String: Opportunity] = [:]

    init(account: AccountStore) {
        self.account = account
        self.settings = AppGroup.read(ScannerSettings.self, from: AppGroup.scannerSettingsURL) ?? .default
    }

    // MARK: - Lifecycle

    func start() {
        guard scanLoop == nil else { return }
        scanLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runScanPass()
                let secs = self?.settings.scanIntervalSeconds ?? 45
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    func stop() {
        scanLoop?.cancel()
        scanLoop = nil
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
            let candidateTickers = Set(candidates.flatMap { $0.legs.map(\.marketTicker) })
            coverage.candidates = candidates.count

            // Stage 4: confirm — fetch real books only for candidate markets, bounded.
            phase = .confirming(candidateTickers.count)
            let books = await fetchBooks(Array(candidateTickers))
            coverage.booksFetched = books.count
            coverage.booksFailed = candidateTickers.count - books.count

            // Stage 5: re-detect with real depth.
            phase = .pricing
            let pricedSnaps = ScanShaping.eventSnapshots(from: events, books: books, now: now)
            let priced = DetectionEngine.scan(ScanSnapshot(events: pricedSnaps, now: now, config: cfg))

            // Stage 6: publish.
            publish(priced, now: now)
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

    private func publish(_ priced: [Opportunity], now: Date) {
        var next: [String: Opportunity] = [:]
        for var o in priced {
            o.freshnessAgeSeconds = now.timeIntervalSince(o.freshnessTimestamp)
            next[o.id] = o
        }
        oppsByID = next
        let cfg = makeConfig()
        let all = DetectionEngine.ranked(Array(oppsByID.values), config: cfg)
        locks = settings.locksEnabled ? all.filter { $0.lane == .lock } : []
        edges = settings.edgesEnabled ? all.filter { $0.lane == .edge } : []
    }

    private func makeConfig() -> DetectorConfig {
        DetectorConfig(
            maxStakeContracts: 100,
            minNetEdgeCents: Decimal(settings.minNetEdgeCents),
            wideSpreadCents: settings.minSpreadCents
        )
    }
}
