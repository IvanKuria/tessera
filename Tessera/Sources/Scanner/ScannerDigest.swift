import Foundation
import KalshiKit
import UserNotifications

/// One row of the daily "Top mispricings" digest — a snapshot of an opportunity
/// at digest time with how long it has survived. Plain facts, no projection.
struct DigestItem: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var lane: OpportunityLane
    var kindLabel: String
    var netEdgeCents: Double
    var netDollars: Double
    var confidence: Double
    /// How long this opportunity has been alive (freshness age), in seconds.
    var survivedSeconds: Double

    init(opp: Opportunity, now: Date) {
        id = opp.id
        title = opp.title
        lane = opp.lane
        kindLabel = opp.kindLabel
        netEdgeCents = NSDecimalNumber(decimal: opp.netEdgePerContractCents).doubleValue
        netDollars = NSDecimalNumber(decimal: opp.netEdgeCents).doubleValue / 100
        confidence = NSDecimalNumber(decimal: opp.confidence).doubleValue
        survivedSeconds = max(0, opp.freshnessAgeSeconds)
    }

    /// "alive 4m" / "alive 38s" — honest survival, not a guarantee of continuation.
    var survivalLabel: String {
        if survivedSeconds < 90 { return "alive \(Int(survivedSeconds))s" }
        return "alive \(Int(survivedSeconds / 60))m"
    }
}

/// The day's best mispricings, built on demand. Forward-only and honest: it
/// reports what's live right now and how long it has held — never hypothetical
/// returns. At most one notification per day is posted (cadence-capped upstream).
struct ScannerDigest: Sendable {
    var generatedAt: Date
    var locks: [DigestItem]
    var edges: [DigestItem]

    var isEmpty: Bool { locks.isEmpty && edges.isEmpty }

    /// Posts the single daily notification summarising the top mispricings.
    func postNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Today's top mispricings"
        content.body = summaryLine
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private var summaryLine: String {
        if isEmpty { return "No actionable mispricings surfaced today." }
        var parts: [String] = []
        if let best = locks.first {
            parts.append(String(format: "Best lock: net %.0f¢/contract", best.netEdgeCents))
        }
        if let best = edges.first {
            parts.append(String(format: "Top edge: %d%% confidence", Int(best.confidence * 100)))
        }
        return parts.joined(separator: " · ")
    }
}
