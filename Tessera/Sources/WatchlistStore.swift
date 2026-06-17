import Foundation
import KalshiKit

/// A single tradeable outcome within an event (one Kalshi market), display-ready.
struct OutcomeVM: Identifiable, Sendable, Hashable {
    let id: String          // market ticker
    let label: String       // cleaned outcome label
    let yesCents: Int?       // buy-YES price
    let noCents: Int?        // buy-NO price
    let percent: Int?        // implied probability 0…100
    let volume: Int
}

/// An event grouping one or more outcomes — the unit shown as a card.
struct EventVM: Identifiable, Sendable, Hashable {
    let id: String          // event ticker
    let title: String       // the question
    let category: String
    let totalVolume: Int
    let closeTime: Date?
    let outcomes: [OutcomeVM]   // sorted by probability desc

    var isBinary: Bool { outcomes.count == 1 }
    var topOutcome: OutcomeVM? { outcomes.first }
}

/// The app's source of truth. An I/O `actor` (`KalshiClient`) does networking off
/// the main thread; this `@MainActor @Observable` store shapes the result into
/// liquidity-filtered event view models and drives SwiftUI.
@MainActor
@Observable
final class WatchlistStore {
    private(set) var events: [EventVM] = []
    private(set) var categories: [String] = ["All"]
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    /// Top event's implied % for the menu-bar glance.
    var menuBarTitle: String {
        guard let percent = events.first?.topOutcome?.percent else { return "Tessera" }
        return "\(percent)%"
    }

    private let client = KalshiClient(environment: .production)
    private let cacheURL: URL
    private var refreshLoop: Task<Void, Never>?

    init() {
        cacheURL = URL.applicationSupportDirectory.appending(path: "Tessera/events.json")
        loadCache()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Events carry clean questions + categories and group their outcomes —
            // a far better basis for the UI than raw markets.
            let response = try await client.events(
                status: "open", withNestedMarkets: true, limit: 200
            )
            apply(events: response.events)
            lastUpdated = Date()
            errorMessage = nil
            saveCache(response.events)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(events rawEvents: [Event]) {
        let vms = Self.build(from: rawEvents)
        events = vms
        categories = ["All"] + vms.map(\.category).uniqued().sorted()
    }

    // MARK: - Shaping

    private static let iso = ISO8601DateFormatter()

    static func build(from rawEvents: [Event]) -> [EventVM] {
        var result: [EventVM] = []
        for event in rawEvents {
            // Drop multivariate same-game parlays (KXMVE…) — illiquid, ugly titles.
            guard !event.eventTicker.hasPrefix("KXMVE") else { continue }
            let category = event.category.flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
            if category.lowercased().contains("multivariate") { continue }

            var outcomes: [OutcomeVM] = []
            var totalVolume = 0
            for market in event.markets ?? [] {
                let volume = market.volumeFp.map { Int(NSDecimalNumber(decimal: $0.value).doubleValue) } ?? 0
                let percent = market.impliedPercent
                // Keep only outcomes with real pricing or activity.
                guard (percent ?? 0) > 0 || volume > 0 else { continue }
                totalVolume += volume
                outcomes.append(OutcomeVM(
                    id: market.ticker,
                    label: cleanLabel(market.yesSubTitle ?? market.title ?? market.ticker),
                    yesCents: cents(market.yesAskDollars) ?? market.yesAsk,
                    noCents: cents(market.noAskDollars) ?? market.noAsk,
                    percent: percent,
                    volume: volume
                ))
            }
            guard !outcomes.isEmpty, totalVolume > 0 else { continue }
            outcomes.sort { ($0.percent ?? 0) > ($1.percent ?? 0) }

            let close = (event.markets ?? []).compactMap(\.closeTime).first.flatMap { iso.date(from: $0) }
            result.append(EventVM(
                id: event.eventTicker,
                title: event.title,
                category: category,
                totalVolume: totalVolume,
                closeTime: close,
                outcomes: outcomes
            ))
        }
        result.sort { $0.totalVolume > $1.totalVolume }
        return Array(result.prefix(60))
    }

    private static func cents(_ value: KalshiDecimal?) -> Int? {
        guard let value else { return nil }
        return Int(NSDecimalNumber(decimal: value.value * 100).doubleValue.rounded())
    }

    private static func cleanLabel(_ raw: String) -> String {
        var s = raw
        for prefix in ["yes ", "no ", "Yes ", "No "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        // Combo titles are comma-joined; show only the first clause.
        if let comma = s.firstIndex(of: ",") { s = String(s[..<comma]) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Disk cache (instant cold-launch render)

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? KalshiJSON.decoder.decode([Event].self, from: data)
        else { return }
        apply(events: cached)
    }

    private func saveCache(_ rawEvents: [Event]) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? KalshiJSON.encoder.encode(rawEvents) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

private extension Sequence where Element: Hashable {
    /// Order-preserving de-duplication.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
