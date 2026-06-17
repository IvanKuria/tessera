import SwiftUI
import KalshiKit

/// A pending trade to present in the ticket sheet.
struct TradeTarget: Identifiable, Hashable {
    let id = UUID()
    let marketTicker: String
    let eventTitle: String
    let side: OrderSide
}

/// The home feed: Kalshi-style top bar + category tabs + a grid of event cards,
/// with navigation into the detail screen and a trade-ticket sheet.
struct DashboardView: View {
    var store: WatchlistStore
    var account: AccountStore

    @State private var category = "All"
    @State private var path: [EventVM] = []
    @State private var tradeTarget: TradeTarget?

    private var filtered: [EventVM] {
        category == "All" ? store.events : store.events.filter { $0.category == category }
    }
    private let columns = [GridItem(.adaptive(minimum: 380, maximum: 540), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    categoryBar
                    Divider().overlay(Theme.divider)
                    feed
                }
            }
            .navigationDestination(for: EventVM.self) { event in
                DetailView(event: event, account: account, onBuy: { ticker, side in
                    tradeTarget = TradeTarget(marketTicker: ticker, eventTitle: event.title, side: side)
                })
                .background(Theme.bg)
            }
        }
        .tint(Theme.yes)
        .sheet(item: $tradeTarget) { target in
            TradeTicketView(account: account,
                            marketTicker: target.marketTicker,
                            eventTitle: target.eventTitle,
                            initialSide: target.side)
                .frame(width: 380, height: 580)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Wordmark()
            Text("for Kalshi · unofficial")
                .font(Theme.ui(11)).foregroundStyle(Theme.textTertiary)
            Spacer()
            LiveDot()
            Text("\(store.events.count) markets")
                .font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: Category tabs

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(store.categories, id: \.self) { cat in
                    CategoryTab(title: cat, selected: cat == category) {
                        withAnimation(.easeOut(duration: 0.18)) { category = cat }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 40)
    }

    // MARK: Feed

    @ViewBuilder private var feed: some View {
        if let error = store.errorMessage, store.events.isEmpty {
            emptyState(icon: "exclamationmark.triangle", title: "Couldn’t load markets", subtitle: error)
        } else if store.events.isEmpty {
            emptyState(icon: "chart.line.uptrend.xyaxis", title: "Loading markets…", subtitle: "Fetching live odds from Kalshi")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filtered) { event in
                        EventCardView(
                            event: event,
                            onOpen: { path.append(event) },
                            onBuy: { ticker, side in
                                tradeTarget = TradeTarget(marketTicker: ticker, eventTitle: event.title, side: side)
                            }
                        )
                    }
                }
                .padding(18)
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.textTertiary)
            Text(title).font(Theme.condensed(18, .semibold)).foregroundStyle(Theme.text)
            Text(subtitle).font(Theme.ui(12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
