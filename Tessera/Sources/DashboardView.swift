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
    @State private var showOnboarding = false
    @State private var showPortfolio = false

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
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(account: account, onDone: { showOnboarding = false })
                .frame(width: 470, height: 640)
        }
        .sheet(isPresented: $showPortfolio) {
            PortfolioView(store: PortfolioStore(client: account.authedClient)) {
                showPortfolio = false
            }
            .frame(width: 580, height: 700)
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
            accountChip
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var accountChip: some View {
        if account.isSignedIn {
            Menu {
                Button("Portfolio") { showPortfolio = true }
                Button("Refresh balance") { Task { await account.refreshAccount() } }
                Button("Sign out", role: .destructive) { account.signOut() }
            } label: {
                HStack(spacing: 6) {
                    Text(account.env == .demo ? "DEMO" : "LIVE")
                        .font(Theme.ui(9, .bold)).tracking(0.6)
                        .foregroundStyle(account.env == .demo ? Theme.textSecondary : Theme.no)
                    Text(balanceText).font(Theme.num(12, .semibold)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Theme.subtle))
            }
            .menuStyle(.borderlessButton).fixedSize()
        } else {
            Button { showOnboarding = true } label: {
                Text("Connect").font(Theme.ui(12, .semibold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.yes))
            }
            .buttonStyle(.plain)
        }
    }

    private var balanceText: String {
        guard let cents = account.balanceCents else { return "—" }
        return String(format: "$%.2f", Double(cents) / 100)
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
