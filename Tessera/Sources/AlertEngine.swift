import Foundation
import KalshiKit
import UserNotifications

/// A user-defined price/probability alert on one market.
///
/// `direction` is derived from `crossesUpward` so the model stays trivially
/// `Codable` (the SDK's `TriggerDirection` isn't `Codable`).
struct AlertRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var marketTicker: String
    var label: String
    var thresholdCents: Int
    /// `true` → notify when the price rises to/through the threshold;
    /// `false` → when it falls to/through it.
    var crossesUpward: Bool
    var enabled: Bool = true

    var direction: TriggerDirection { crossesUpward ? .above : .below }
}

/// Watches the live ticker feed and posts a native macOS notification when a
/// market crosses an alert threshold. Read-only: no auth, no orders.
///
/// Crossing detection is **edge-triggered** via the SDK's tested
/// `triggerShouldFire` — a market resting past the threshold doesn't re-notify
/// every tick; it must actually cross. Baselines reset on (re)connect so an
/// offline gap doesn't fire a stale alert.
@MainActor
@Observable
final class AlertEngine {
    private(set) var rules: [AlertRule]
    private(set) var connection: SocketConnectionState = .disconnected

    private var socket: KalshiSocket?
    private var consumeTask: Task<Void, Never>?
    /// Last seen price per market — the baseline for edge detection.
    private var lastCents: [String: Int] = [:]
    private var authorized = false

    init() {
        rules = AppGroup.read([AlertRule].self, from: AppGroup.alertRulesURL) ?? []
    }

    // MARK: - Lifecycle

    /// Requests notification permission and starts the live feed. Idempotent.
    func start() async {
        await requestAuthorizationIfNeeded()
        restartFeed()
    }

    func stop() {
        consumeTask?.cancel(); consumeTask = nil
        Task { [socket] in await socket?.disconnect() }
        socket = nil
        connection = .disconnected
    }

    // MARK: - Rule management

    func addRule(_ rule: AlertRule) {
        rules.append(rule)
        persist()
        restartFeed()
    }

    func removeRule(_ rule: AlertRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
        restartFeed()
    }

    func setEnabled(_ enabled: Bool, for rule: AlertRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i].enabled = enabled
        persist()
        restartFeed()
    }

    private func persist() {
        AppGroup.write(rules, to: AppGroup.alertRulesURL)
    }

    // MARK: - Feed

    /// The distinct set of markets we currently need ticker updates for.
    private var watchedMarkets: [String] {
        Array(Set(rules.filter(\.enabled).map(\.marketTicker))).sorted()
    }

    /// Tears down and rebuilds the socket for the current watch set. Simpler and
    /// safer than incremental (un)subscribe when rules change.
    private func restartFeed() {
        consumeTask?.cancel()
        let old = socket
        socket = nil
        Task { await old?.disconnect() }

        let markets = watchedMarkets
        guard !markets.isEmpty else { connection = .disconnected; return }

        lastCents.removeAll()
        let sock = KalshiSocket(environment: .production)
        socket = sock
        consumeTask = Task { [weak self] in
            let events = await sock.events()
            await sock.connect()
            await sock.subscribe(to: [.ticker], markets: markets)
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
            lastCents.removeAll() // reset baselines so a reconnect gap can't fire
        case .disconnected:
            connection = .disconnected
        case .ticker(let t):
            evaluate(t)
        default:
            break
        }
    }

    private func evaluate(_ t: TickerUpdate) {
        guard let ticker = t.marketTicker, let current = t.lastCents else { return }
        let previous = lastCents[ticker]
        lastCents[ticker] = current

        for rule in rules where rule.enabled && rule.marketTicker == ticker {
            if triggerShouldFire(
                previousCents: previous,
                currentCents: current,
                thresholdCents: rule.thresholdCents,
                direction: rule.direction
            ) {
                postNotification(for: rule, currentCents: current)
            }
        }
    }

    // MARK: - Notifications

    private func requestAuthorizationIfNeeded() async {
        guard !authorized else { return }
        let center = UNUserNotificationCenter.current()
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func postNotification(for rule: AlertRule, currentCents: Int) {
        let content = UNMutableNotificationContent()
        content.title = rule.label
        let arrow = rule.crossesUpward ? "rose to" : "fell to"
        content.body = "\(arrow) \(currentCents)¢ (alert at \(rule.thresholdCents)¢)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
