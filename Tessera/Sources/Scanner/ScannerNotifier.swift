import Foundation
import KalshiKit
import UserNotifications

/// Posts a native macOS notification when an opportunity *freshly crosses up* into
/// the actionable net-edge band — never on every scan pass while it sits there.
///
/// Mirrors `AlertEngine`'s `UNUserNotificationCenter` usage (auth request,
/// immediate `trigger: nil` delivery) and its **edge-triggered** discipline: we
/// remember each opportunity's last-fired net edge and only fire when it has just
/// risen from below the threshold to at-or-above it. Two guards keep it quiet:
/// a per-id cooldown, and pruning of ids that have left the scan.
///
/// Honesty: copy states net edge × size as a plain estimate; never "guaranteed",
/// never "you would have made". Tracked opportunities (the user explicitly tapped
/// "Track & alert me") bypass the global threshold but still respect the cooldown
/// and the edge-triggered crossing, so a tracked-but-flat opp doesn't spam.
@MainActor
final class ScannerNotifier {
    /// The net edge (cents) at which each id last fired — the baseline for the
    /// edge-triggered crossing test.
    private var lastFiredNetEdge: [String: Decimal] = [:]
    /// When each id last fired — the cooldown baseline.
    private var lastFired: [String: Date] = [:]
    private var authorized = false

    /// Requests notification permission once. Call from `ScannerStore.start()`.
    func requestAuthorizationIfNeeded() async {
        guard !authorized else { return }
        let center = UNUserNotificationCenter.current()
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Evaluates one opportunity and fires a notification iff it *just* became
    /// actionable. `tracked` ids bypass the global min-edge / locks-only gates.
    func consider(
        _ opp: Opportunity,
        settings: ScannerSettings,
        tracked: Set<String> = [],
        now: Date = .now
    ) {
        let isTracked = tracked.contains(opp.id)
        guard settings.alertsEnabled || isTracked else { return }

        // Lane gate (skipped for explicitly-tracked opps).
        if !isTracked && settings.alertLocksOnly && opp.lane != .lock { return }

        // Actionable threshold (tracked opps alert on any positive crossing).
        let threshold: Decimal = isTracked ? 1 : Decimal(settings.alertMinNetEdgeCents)
        let net = opp.netEdgeCents
        let actionable = net >= threshold

        let previous = lastFiredNetEdge[opp.id]

        guard actionable else {
            // No longer actionable — clear the baseline so a later re-cross fires.
            lastFiredNetEdge[opp.id] = nil
            return
        }

        // Edge-triggered: fire only on a FRESH crossing up — newly seen, or its
        // last-fired edge was below the threshold and it's now at/above it. A
        // resting actionable opp does NOT re-fire every pass.
        let justCrossed = (previous == nil) || (previous! < threshold)
        guard justCrossed else { return }

        // Cooldown.
        if let last = lastFired[opp.id],
           now.timeIntervalSince(last) <= Double(settings.alertCooldownSeconds) {
            return
        }

        post(opp, isTracked: isTracked)
        lastFired[opp.id] = now
        lastFiredNetEdge[opp.id] = net
    }

    /// Drops bookkeeping for ids that have left the scan, so the maps don't grow
    /// unbounded and a returning id re-fires as a fresh crossing.
    func prune(keeping live: Set<String>) {
        lastFired = lastFired.filter { live.contains($0.key) }
        lastFiredNetEdge = lastFiredNetEdge.filter { live.contains($0.key) }
    }

    // MARK: - Notification

    private func post(_ opp: Opportunity, isTracked: Bool) {
        let content = UNMutableNotificationContent()
        let prefix = opp.lane == .lock ? "Lock" : "Edge"
        content.title = "\(prefix): \(opp.title)"
        content.body = bodyLine(opp) + (isTracked ? " · tracked" : "")
        content.sound = .default
        content.userInfo = ["oppID": opp.id]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// "Net edge 6¢ × 120 ≈ $7.20" — net edge per contract, size, and dollar total.
    private func bodyLine(_ opp: Opportunity) -> String {
        let perContract = NSDecimalNumber(decimal: opp.netEdgePerContractCents).doubleValue
        let qty = opp.maxContractsInt
        let total = NSDecimalNumber(decimal: opp.netEdgeCents).doubleValue / 100
        return String(format: "Net edge %.0f¢ × %d ≈ $%.2f", perContract, qty, total)
    }
}
