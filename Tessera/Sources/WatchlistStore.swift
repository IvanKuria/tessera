import Foundation
import KalshiKit

/// The app's single source of truth: live Kalshi market data for the menu bar
/// and main window. An I/O `actor` (`KalshiClient`) does the networking off the
/// main thread; this `@MainActor @Observable` store consumes it and drives SwiftUI.
///
/// On launch it renders a cached snapshot immediately, then refreshes on a gentle
/// timer (well within Kalshi's keyless read budget).
@MainActor
@Observable
final class WatchlistStore {
    private(set) var markets: [Market] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    /// The market shown in the menu-bar glance (top of the list for now).
    var tracked: Market? { markets.first }

    /// Compact string for the menu-bar title, e.g. `47%`.
    var menuBarTitle: String {
        guard let percent = tracked?.impliedPercent else { return "Tessera" }
        return "\(percent)%"
    }

    private let client = KalshiClient(environment: .production)
    private let cacheURL: URL
    private var refreshLoop: Task<Void, Never>?

    init() {
        cacheURL = URL.applicationSupportDirectory.appending(path: "Tessera/markets.json")
        loadCache()
        // Kick off a gentle refresh loop. Weakly captured so it ends if the
        // store is ever released (it lives for the app's lifetime in practice).
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Fetches the most active open markets.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.markets(status: "open", limit: 25)
            markets = response.markets
            lastUpdated = Date()
            errorMessage = nil
            saveCache()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Disk cache (instant cold-launch render)

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? KalshiJSON.decoder.decode([Market].self, from: data)
        else { return }
        markets = cached
    }

    private func saveCache() {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? KalshiJSON.encoder.encode(markets) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
