import SwiftUI
import KalshiKit

/// The app shell: a Mac-native sidebar (Markets / Portfolio / Alerts & Triggers)
/// with the account at the bottom, and the selected section in the detail column.
struct RootView: View {
    var store: WatchlistStore
    var account: AccountStore
    var alerts: AlertEngine
    var triggers: TriggerEngine

    enum Section: String, Hashable, CaseIterable {
        case markets, portfolio, automation
        var title: String {
            switch self {
            case .markets:    return "Markets"
            case .portfolio:  return "Portfolio"
            case .automation: return "Alerts & Triggers"
            }
        }
        var icon: String {
            switch self {
            case .markets:    return "chart.line.uptrend.xyaxis"
            case .portfolio:  return "briefcase.fill"
            case .automation: return "bell.badge.fill"
            }
        }
    }

    @State private var selection: Section? = .markets
    @State private var portfolioStore: PortfolioStore
    @State private var showOnboarding = false
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue

    init(store: WatchlistStore, account: AccountStore, alerts: AlertEngine, triggers: TriggerEngine) {
        self.store = store
        self.account = account
        self.alerts = alerts
        self.triggers = triggers
        _portfolioStore = State(initialValue: PortfolioStore(account: account))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 300)
        } detail: {
            detail
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(account: account) { showOnboarding = false }
                .frame(width: 470, height: 640)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(Section.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)

            Divider()
            VStack(spacing: 10) {
                accountFooter
                appearancePicker
            }
            .padding(12)
        }
        .safeAreaInset(edge: .top) {
            HStack { Wordmark(); Spacer() }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
        }
    }

    /// Light / Dark / System appearance control. Same segmented style as the
    /// Line/Candles chart toggle (subtle track + lifted selected thumb, all Theme
    /// colors). Writes the shared `appAppearance` preference that `TesseraApp`
    /// reads to drive `preferredColorScheme`.
    private var appearancePicker: some View {
        HStack(spacing: 0) {
            ForEach(AppAppearance.allCases) { option in
                appearanceButton(option)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
    }

    private func appearanceButton(_ option: AppAppearance) -> some View {
        let selected = appearanceRaw == option.rawValue
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { appearanceRaw = option.rawValue }
        } label: {
            Image(systemName: option.symbol)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.surface : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.label)
    }

    @ViewBuilder private var accountFooter: some View {
        if account.isSignedIn {
            Menu {
                Button("Refresh balance") { Task { await account.refreshAccount() } }
                Button {
                    KalshiLinks.open(KalshiLinks.manageFunds)
                } label: {
                    Label("Deposit / withdraw on Kalshi ↗", systemImage: "arrow.up.right.square")
                }
                Divider()
                if account.env == .demo {
                    Button("Switch to Production (real money)") { account.setEnv(.production) }
                } else {
                    Button("Switch to Demo") { account.setEnv(.demo) }
                }
                Button("Sign out", role: .destructive) { account.signOut() }
            } label: {
                HStack(spacing: 9) {
                    Circle().fill(account.env == .production ? Theme.no : Theme.yes)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.env == .demo ? "Demo account" : "Live account")
                            .font(Theme.ui(11, .semibold)).foregroundStyle(Theme.text)
                        Text(balanceText).font(Theme.num(12, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis").foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtle))
            }
            .menuStyle(.borderlessButton)
        } else {
            Button { showOnboarding = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 11))
                    Text("Connect Kalshi key").font(Theme.ui(12, .semibold))
                }
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Capsule().fill(Theme.yes))
            }
            .buttonStyle(.plain)
        }
    }

    private var balanceText: String {
        guard let cents = account.balanceCents else { return "Balance —" }
        return String(format: "$%.2f", Double(cents) / 100)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch selection ?? .markets {
        case .markets:
            DashboardView(store: store, account: account, alerts: alerts)
        case .portfolio:
            PortfolioView(store: portfolioStore, showsClose: false)
                .id(account.isSignedIn)  // reload section when sign-in changes
        case .automation:
            AutomationView(alerts: alerts, triggers: triggers)
        }
    }
}
