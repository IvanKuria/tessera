import Foundation
import KalshiKit

/// Drives the Portfolio screen: balance, open positions, resting orders, recent
/// fills, and settled markets. Networking is performed by the injected
/// `KalshiClient` actor off the main thread; this `@MainActor @Observable` store
/// shapes the result for SwiftUI.
///
/// Like `DetailStore`, per-section failures are tolerated so one dead endpoint
/// never blanks the screen. Only a balance failure surfaces as `errorMessage`.
@MainActor
@Observable
final class PortfolioStore {
    // MARK: - Observable state

    /// Available balance in cents.
    private(set) var balanceCents: Int?
    /// Total portfolio value in cents (balance + open exposure marked to market).
    private(set) var portfolioValueCents: Int?
    private(set) var positions: [MarketPosition] = []
    private(set) var openOrders: [Order] = []
    private(set) var fills: [Fill] = []
    private(set) var settlements: [Settlement] = []

    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Wiring

    /// The signed REST client, shared from `AccountStore`. `nil` when signed out.
    private let client: KalshiClient?

    /// Stores the client; performs NO networking (keep init cheap for SwiftUI).
    init(client: KalshiClient?) {
        self.client = client
    }

    // MARK: - Load

    /// Loads every portfolio section concurrently, tolerating per-section
    /// failures. Only a balance failure sets `errorMessage`.
    func load() async {
        guard let client else {
            errorMessage = "Connect your Kalshi API key first."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let balanceResult = Self.result { try await client.balance() }
        async let positionsResult = Self.result {
            try await client.positions(ticker: nil, limit: 200, cursor: nil).marketPositions ?? []
        }
        async let ordersResult = Self.result {
            try await client.orders(ticker: nil, status: nil, cursor: nil).orders
        }
        async let fillsResult = Self.result {
            try await client.fills(ticker: nil, limit: 50, cursor: nil).fills
        }
        async let settlementsResult = Self.result {
            try await client.settlements(limit: 50, cursor: nil).settlements
        }

        let balance = await balanceResult
        let pos = await positionsResult
        let ord = await ordersResult
        let fil = await fillsResult
        let set = await settlementsResult

        if let b = balance.value {
            balanceCents = b.balance
            portfolioValueCents = Self.cents(from: b.portfolioValueDollars) ?? b.balance
        } else {
            errorMessage = balance.error
        }

        // Only the markets the user actually holds.
        positions = (pos.value ?? positions).filter { ($0.position ?? 0) != 0 }

        // Keep only live (resting / open) orders.
        openOrders = (ord.value ?? openOrders).filter { Self.isOpen($0) }

        fills = fil.value ?? fills
        settlements = set.value ?? settlements
    }

    /// Cancels a resting order, then reloads the orders list.
    func cancel(orderId: String) async {
        guard let client else { return }
        do {
            try await client.cancelOrder(orderId: orderId)
        } catch {
            errorMessage = Self.readable(error)
        }
        await reloadOrders()
    }

    /// Refreshes just the open-orders section (after a cancel).
    private func reloadOrders() async {
        guard let client else { return }
        let result = await Self.result {
            try await client.orders(ticker: nil, status: nil, cursor: nil).orders
        }
        if let orders = result.value {
            openOrders = orders.filter { Self.isOpen($0) }
        }
    }

    // MARK: - Computed summary

    /// Total realized P&L across all positions, in dollars.
    var totalRealizedPnl: Decimal {
        positions.reduce(Decimal(0)) { $0 + ($1.realizedPnlDollars?.value ?? 0) }
    }

    /// Total open market exposure across all positions, in dollars.
    var totalExposure: Decimal {
        positions.reduce(Decimal(0)) { $0 + ($1.marketExposureDollars?.value ?? 0) }
    }

    // MARK: - Helpers

    /// True for orders the user can still act on (resting / open / partially filled).
    private static func isOpen(_ order: Order) -> Bool {
        let status = (order.status ?? "").lowercased()
        if status.contains("resting") || status.contains("open") || status.contains("pending") {
            return true
        }
        // No status reported but still has unfilled contracts → treat as live.
        if status.isEmpty, (order.remainingCount ?? order.count ?? 0) > 0 {
            return true
        }
        return false
    }

    /// Converts a dollar `KalshiDecimal` to integer cents.
    private static func cents(from dollars: KalshiDecimal?) -> Int? {
        guard let dollars else { return nil }
        let cents = dollars.value * 100
        return NSDecimalNumber(decimal: cents).rounding(accordingToBehavior:
            NSDecimalNumberHandler(roundingMode: .plain, scale: 0,
                                   raiseOnExactness: false, raiseOnOverflow: false,
                                   raiseOnUnderflow: false, raiseOnDivideByZero: false)
        ).intValue
    }

    private static func readable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Per-section failure tolerance

    private struct Outcome<T: Sendable>: Sendable {
        var value: T?
        var error: String?
    }

    private nonisolated static func result<T: Sendable>(
        _ op: @Sendable () async throws -> T
    ) async -> Outcome<T> {
        do {
            return Outcome(value: try await op(), error: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return Outcome(value: nil, error: message)
        }
    }
}
