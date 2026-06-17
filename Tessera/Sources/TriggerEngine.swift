import Foundation
import KalshiKit
import UserNotifications

/// Lifecycle of a synthetic trigger.
enum TriggerState: String, Codable, Sendable {
    case armed      // watching the feed
    case firing     // crossing detected, order being placed (in-flight guard)
    case filled     // order placed successfully
    case cancelled  // cancelled by the user or an OCO sibling firing
    case error      // placement failed; see lastErrorMessage, manual re-arm
}

/// A client-side synthetic stop-loss / take-profit / OCO leg. Kalshi has no native
/// stop order, so we watch the ticker and place a limit order when the price
/// crosses `thresholdCents`.
struct SyntheticTrigger: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var marketTicker: String
    var label: String

    // Crossing condition.
    var thresholdCents: Int
    /// `true` → fire when price rises to/through the threshold (take-profit on a
    /// long / stop on a short); `false` → falls to/through it (stop-loss on a long).
    var crossesUpward: Bool

    // The protective order placed on fire.
    var action: OrderAction      // typically .sell to exit a position
    var side: OrderSide          // .yes / .no
    var count: Int
    var limitCents: Int          // limit price for the exit order

    /// Triggers sharing a group are one-cancels-other: when one fires, its
    /// armed siblings are cancelled.
    var ocoGroup: UUID?

    var state: TriggerState = .armed
    var lastErrorMessage: String?

    var direction: TriggerDirection { crossesUpward ? .above : .below }

    /// STABLE idempotency key. A retry after an ambiguous timeout dedupes to the
    /// same server order instead of firing twice. Fires once per trigger ever.
    var clientOrderId: String { "tessera-trigger-\(id.uuidString)" }
}

/// Watches the live ticker and fires synthetic triggers as limit orders through
/// `AccountStore`. Best-effort and LOCAL: it only runs while the app is open.
///
/// Safety design:
/// - Crossing detection is the SDK's tested `triggerShouldFire` (edge-triggered).
/// - A synchronous `firing` guard + stable `clientOrderId` prevent double-fires.
/// - Baselines reset on (re)connect; if a price is already past a threshold on
///   the first post-reconnect tick, we NOTIFY ("moved past while offline")
///   instead of auto-firing into an unknown book.
@MainActor
@Observable
final class TriggerEngine {
    private(set) var triggers: [SyntheticTrigger]
    private(set) var connection: SocketConnectionState = .disconnected

    private let account: AccountStore
    private var socket: KalshiSocket?
    private var consumeTask: Task<Void, Never>?
    private var lastCents: [String: Int] = [:]
    /// Triggers currently placing an order — synchronous double-fire guard.
    private var firing: Set<UUID> = []
    /// Markets awaiting their first tick after a (re)connect, for the offline-gap check.
    private var reconnectPending: Set<String> = []

    init(account: AccountStore) {
        self.account = account
        triggers = AppGroup.read([SyntheticTrigger].self, from: AppGroup.triggersURL) ?? []
    }

    // MARK: - Lifecycle

    func start() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        restartFeed()
    }

    func stop() {
        consumeTask?.cancel(); consumeTask = nil
        Task { [socket] in await socket?.disconnect() }
        socket = nil
        connection = .disconnected
    }

    // MARK: - Trigger management

    func add(_ trigger: SyntheticTrigger) {
        triggers.append(trigger)
        persist()
        restartFeed()
    }

    func remove(_ trigger: SyntheticTrigger) {
        triggers.removeAll { $0.id == trigger.id }
        persist()
        restartFeed()
    }

    /// Resets an errored/cancelled/filled trigger back to armed.
    func rearm(_ trigger: SyntheticTrigger) {
        guard let i = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[i].state = .armed
        triggers[i].lastErrorMessage = nil
        persist()
        restartFeed()
    }

    private func persist() {
        AppGroup.write(triggers, to: AppGroup.triggersURL)
    }

    // MARK: - Feed

    private var watchedMarkets: [String] {
        Array(Set(triggers.filter { $0.state == .armed }.map(\.marketTicker))).sorted()
    }

    private func restartFeed() {
        consumeTask?.cancel()
        let old = socket
        socket = nil
        Task { await old?.disconnect() }

        let markets = watchedMarkets
        guard !markets.isEmpty else { connection = .disconnected; return }

        lastCents.removeAll()
        let sock = KalshiSocket(environment: account.env.kalshi)
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
            lastCents.removeAll()
            reconnectPending = Set(watchedMarkets) // first tick per market gets the gap check
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

        // Offline-gap check: on the first tick after reconnect, if a trigger is
        // already past its threshold, notify instead of (not) firing.
        let firstAfterReconnect = reconnectPending.remove(ticker) != nil

        for trigger in triggers where trigger.state == .armed && trigger.marketTicker == ticker {
            if firstAfterReconnect, isPastThreshold(trigger, current: current) {
                notify(
                    title: trigger.label,
                    body: "Market was \(current)¢ on reconnect — past your \(trigger.thresholdCents)¢ trigger. Not auto-fired; review and re-arm."
                )
                continue
            }
            guard !firing.contains(trigger.id) else { continue }
            if triggerShouldFire(
                previousCents: previous,
                currentCents: current,
                thresholdCents: trigger.thresholdCents,
                direction: trigger.direction
            ) {
                beginFiring(trigger, at: current)
            }
        }
    }

    private func isPastThreshold(_ trigger: SyntheticTrigger, current: Int) -> Bool {
        trigger.crossesUpward ? current >= trigger.thresholdCents
                              : current <= trigger.thresholdCents
    }

    // MARK: - Firing

    /// Synchronously marks the trigger firing + cancels OCO siblings, then places
    /// the order on a child task so the event loop keeps flowing.
    private func beginFiring(_ trigger: SyntheticTrigger, at current: Int) {
        firing.insert(trigger.id)
        setState(.firing, for: trigger.id)

        // OCO: cancel armed siblings in the same group.
        if let group = trigger.ocoGroup {
            for sibling in triggers where sibling.ocoGroup == group
                && sibling.id != trigger.id && sibling.state == .armed {
                setState(.cancelled, for: sibling.id)
            }
        }
        persist()

        Task { [weak self] in await self?.placeOrder(for: trigger, at: current) }
    }

    private func placeOrder(for trigger: SyntheticTrigger, at current: Int) async {
        let result = await account.placeOrder(
            marketTicker: trigger.marketTicker,
            action: trigger.action,
            side: trigger.side,
            count: trigger.count,
            limitCents: trigger.limitCents,
            clientOrderId: trigger.clientOrderId
        )
        firing.remove(trigger.id)

        switch result {
        case .success:
            setState(.filled, for: trigger.id)
            notify(title: trigger.label, body: "Triggered at \(current)¢ — order placed (\(trigger.count) @ \(trigger.limitCents)¢).")
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            setError(message, for: trigger.id)
            notify(title: trigger.label, body: "Trigger fired but the order failed: \(message). Re-arm to retry.")
        }
        persist()
    }

    // MARK: - State helpers

    private func setState(_ state: TriggerState, for id: UUID) {
        guard let i = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[i].state = state
    }

    private func setError(_ message: String, for id: UUID) {
        guard let i = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[i].state = .error
        triggers[i].lastErrorMessage = message
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
