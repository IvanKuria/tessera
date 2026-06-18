import Foundation

/// User-tunable knobs for the scanner: scan cadence, discovery caps, edge/lock
/// thresholds, freshness limits, and alerting. Persisted to the App Group so the
/// settings survive relaunch (and, later, can be shared with surfaces that read
/// the same container). Pure value type — no I/O lives here.
struct ScannerSettings: Codable, Sendable, Equatable {
    var scanIntervalSeconds: Int = 45
    var maxEventsScanned: Int = 3_000
    var maxConcurrentBookFetches: Int = 6
    var bookDepth: Int = 10
    var minNetEdgeCents: Int = 2
    var minQuoteEdgeCents: Int = 1
    var minSpreadCents: Int = 8
    var locksEnabled = true
    var edgesEnabled = true
    var categories: Set<String> = []
    var useOrderbookDelta = false
    var maxStaleSeconds: Int = 90
    var maxLiveSilenceSeconds: Int = 30
    var alertsEnabled = true
    var alertMinNetEdgeCents: Int = 5
    var alertCooldownSeconds: Int = 300
    var alertLocksOnly = false
    /// Opt-in daily "Top mispricings" digest, cadence-capped to one notification/day.
    var digestEnabled = false
    static let `default` = ScannerSettings()
}
