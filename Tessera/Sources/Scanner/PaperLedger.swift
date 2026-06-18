import Foundation
import KalshiKit

/// One forward-only paper-trade record. Stamped at the moment the user taps
/// "Paper-trade this" — NEVER backfilled, NEVER a hypothetical "you would have
/// made $X". It captures what the calculator showed at open, in this size.
struct PaperEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var oppID: String
    var title: String
    var lane: OpportunityLane
    var kindLabel: String
    var openedAt: Date
    var stakeDollars: Double
    var contracts: Int
    /// Net edge per contract (cents) the engine showed at open.
    var netEdgeCentsAtOpen: Double
    /// Modelled net-of-fee dollars captured at open (forward only — what the engine
    /// projected at this size, recorded the instant the user committed).
    var capturedNetDollars: Double
    var status: Status = .open
    var note: String = ""

    enum Status: String, Codable, Sendable, Hashable { case open, closed }
}

/// Forward-only paper ledger. Persists `[PaperEntry]` to the App Group and exposes
/// honest cumulative stats that reward *finding edge* and *consistency* — never
/// trade count, never hypothetical winnings.
///
/// Every surface that shows this must carry a "Paper — no real money" label and
/// the start date, so it can never be mistaken for realised performance.
@MainActor
@Observable
final class PaperLedger {
    private(set) var entries: [PaperEntry]

    init() {
        entries = AppGroup.read([PaperEntry].self, from: AppGroup.scannerPaperURL) ?? []
    }

    /// The day the ledger began accruing — anchors the honest "started <date>"
    /// banner. `nil` until the first entry exists.
    var startedAt: Date? { entries.map(\.openedAt).min() }

    /// Records the opportunity at the calculator's current size. Stamped "now".
    func record(_ opp: Opportunity, stakeDollars: Double, contracts: Int, at date: Date = Date()) {
        // Net-of-fee dollars at this exact size, derived from the engine's
        // per-contract net edge — not a headline figure, not extrapolated forward.
        let perContractCents = NSDecimalNumber(decimal: opp.netEdgePerContractCents).doubleValue
        let capturedNet = perContractCents * Double(contracts) / 100
        let entry = PaperEntry(
            oppID: opp.id,
            title: opp.title,
            lane: opp.lane,
            kindLabel: opp.kindLabel,
            openedAt: date,
            stakeDollars: stakeDollars,
            contracts: contracts,
            netEdgeCentsAtOpen: perContractCents,
            capturedNetDollars: capturedNet
        )
        entries.append(entry)
        persist()
    }

    func remove(_ entry: PaperEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        AppGroup.write(entries, to: AppGroup.scannerPaperURL)
    }

    // MARK: - Honest stats (edge-found + consistency, NOT frequency)

    /// Cumulative modelled net-of-fee P&L across all entries (forward only).
    var cumulativeNetDollars: Double { entries.reduce(0) { $0 + $1.capturedNetDollars } }

    var entryCount: Int { entries.count }

    var lockCount: Int { entries.filter { $0.lane == .lock }.count }

    /// Average net edge per contract found, in cents — an "edge accuracy"-style
    /// quality metric. Rewards finding *better* edges, not more trades.
    var averageEdgeCents: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.netEdgeCentsAtOpen } / Double(entries.count)
    }

    /// Share of recorded paper trades that were provable locks (a consistency /
    /// discipline signal, not a hype number).
    var lockShare: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(lockCount) / Double(entries.count)
    }
}

/// Tiny observable set of opportunity ids the user explicitly chose to "Track &
/// alert me" on. Persisted to the App Group; `ScannerNotifier` always alerts on a
/// tracked opp (still cooldown- and crossing-gated), regardless of the global
/// min-edge / locks-only settings.
@MainActor
@Observable
final class TrackedStore {
    private(set) var ids: Set<String>

    init() {
        ids = Set(AppGroup.read([String].self, from: AppGroup.scannerTrackedURL) ?? [])
    }

    func isTracked(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        persist()
    }

    func track(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        persist()
    }

    func untrack(_ id: String) {
        guard ids.contains(id) else { return }
        ids.remove(id)
        persist()
    }

    private func persist() {
        AppGroup.write(Array(ids), to: AppGroup.scannerTrackedURL)
    }
}
