import SwiftUI
import KalshiKit

/// The Scanner screen (Slice 3, read-only). Header carries the lane toggle
/// (Locks·n / Edges·n), the Simple/Pro mode toggle, a live dot + freshness
/// readout, and a Filters stub. Body switches between the Simple list of cards
/// and the Pro dense table, with honest loading / empty / offline / error states.
///
/// Tapping a row's CTA selects an opportunity and presents the real execution
/// panel (`OpportunityDetailPanel`, Slice 5) — the dutching calculator, bound
/// legs, explainer, and the legging-gated actions. Appearance follows the
/// system — no `preferredColorScheme` override here.
struct ScannerView: View {
    @Bindable var store: ScannerStore
    var account: AccountStore
    var paper: PaperLedger

    enum Lane: Hashable { case locks, edges }
    enum Mode: String { case simple, pro }
    /// The secondary stickiness strip (spec §5).
    enum Tab: String, CaseIterable { case live, watching, paper, digest
        var title: String {
            switch self {
            case .live:     return "Live"
            case .watching: return "Watching"
            case .paper:    return "Paper P&L"
            case .digest:   return "Digest"
            }
        }
    }

    @State private var lane: Lane = .locks
    @AppStorage("scanner.mode") private var modeRaw = Mode.simple.rawValue
    @State private var tab: Tab = .live
    @State private var selectedOpp: Opportunity?

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .simple }
    private var shownOpps: [Opportunity] { lane == .locks ? store.locks : store.edges }
    private var shownLane: OpportunityLane { lane == .locks ? .lock : .edge }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().overlay(Theme.divider)
            switch tab {
            case .live:
                header
                Divider().overlay(Theme.divider)
                content
            case .watching:
                WatchingTab(store: store) { selectedOpp = $0 }
            case .paper:
                PaperPnLTab(paper: paper)
            case .digest:
                DigestTab(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .sheet(item: $selectedOpp) { opp in
            OpportunityDetailPanel(opp: opp, account: account, paper: paper, tracked: store.tracked) { selectedOpp = nil }
        }
    }

    // MARK: - Stickiness tab strip (Slice 6)

    private var tabStrip: some View {
        HStack(spacing: 22) {
            ForEach(Tab.allCases, id: \.self) { t in
                CategoryTab(title: tabTitle(t), selected: tab == t) {
                    withAnimation(.easeOut(duration: 0.15)) { tab = t }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private func tabTitle(_ t: Tab) -> String {
        switch t {
        case .watching where !store.tracked.ids.isEmpty:
            return "Watching · \(store.tracked.ids.count)"
        case .paper where paper.entryCount > 0:
            return "Paper P&L · \(paper.entryCount)"
        default:
            return t.title
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            LaneModeToggle(
                options: [
                    (.locks, "Locks", store.locks.count),
                    (.edges, "Edges", store.edges.count),
                ],
                selection: $lane
            )

            Spacer()

            // Liveness + freshness readout — honestly reflects the live socket.
            HStack(spacing: 8) {
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Text(phaseLabel).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                } else if let last = store.lastScan {
                    livenessBadge(last: last)
                } else {
                    Text("starting…").font(Theme.ui(11)).foregroundStyle(Theme.textTertiary)
                }
            }

            // Filters stub.
            Button {
                // Filters panel arrives with settings UI (later slice).
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11, weight: .semibold))
                    Text("Filters").font(Theme.ui(12, .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.subtle))
            }
            .buttonStyle(.plain)
            .help("Scan filters (coming soon)")

            // Refresh.
            Button { store.refreshNow() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(7)
                    .background(Circle().fill(Theme.subtle))
            }
            .buttonStyle(.plain)
            .disabled(store.isScanning)
            .help("Scan now")

            LaneModeToggle(
                options: [(Mode.simple, "Simple", nil), (Mode.pro, "Pro", nil)],
                selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })
            )
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var phaseLabel: String {
        switch store.phase {
        case .idle:            return "scanning…"
        case .discovering:     return "discovering markets…"
        case .detecting:       return "detecting…"
        case .confirming(let n): return "confirming \(n) books…"
        case .pricing:         return "pricing…"
        case .degraded(let m): return m
        }
    }

    private func freshnessText(_ last: Date) -> String {
        let secs = Int(Date().timeIntervalSince(last))
        if secs < 5 { return "updated just now" }
        if secs < 90 { return "updated \(secs)s ago" }
        let mins = secs / 60
        return "updated \(mins)m ago"
    }

    /// Header status that honestly reflects the live socket. When there's a watch
    /// set we show Live / Reconnecting / Offline; with nothing surfaced there's no
    /// socket to open, so we just show the REST snapshot freshness (no false alarm).
    @ViewBuilder private func livenessBadge(last: Date) -> some View {
        let hasOpps = !store.locks.isEmpty || !store.edges.isEmpty
        switch store.connection {
        case .connected:
            LiveDot()
            Text("Live · \(freshnessText(last))").font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
        case .connecting:
            Circle().fill(Color(hex: 0xF59F00)).frame(width: 7, height: 7)
            Text("Reconnecting…").font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
        case .disconnected:
            if hasOpps {
                Circle().fill(Color(hex: 0xF59F00)).frame(width: 7, height: 7)
                Text("Offline · \(freshnessText(last))").font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
            } else {
                Circle().fill(Theme.textTertiary).frame(width: 7, height: 7)
                Text(freshnessText(last)).font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if let err = store.lastError, store.lastScan == nil {
            errorState(err)
        } else if store.lastScan == nil {
            loadingState
        } else if shownOpps.isEmpty {
            ScrollView { ScannerEmptyState(lane: shownLane) }
        } else if mode == .simple {
            simpleList
        } else {
            proTable
        }
    }

    private var simpleList: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let err = store.lastError { degradedBanner(err) }
                ForEach(shownOpps) { opp in
                    OpportunityRow(opp: opp) { selectedOpp = opp }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var proTable: some View {
        VStack(spacing: 0) {
            if let err = store.lastError {
                degradedBanner(err).padding(.horizontal, 14).padding(.top, 10)
            }
            OpportunityTableHeader()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shownOpps) { opp in
                        OpportunityTableRow(opp: opp) { selectedOpp = opp }
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in skeletonCard }
        }
        .padding(20)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .redacted(reason: .placeholder)
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("First scan in progress — walking the order books…")
                    .font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 8)
        }
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("LOCK").font(Theme.ui(9, .bold)); Spacer(); Text("updated 0s ago").font(Theme.num(10)) }
            Text("A representative market title that spans the card")
                .font(Theme.ui(15.5, .semibold))
            Text("+0.0¢ net edge / contract").font(Theme.num(28, .semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light)).foregroundStyle(Theme.textTertiary)
            Text("Couldn't complete a scan").font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text)
            Text(message)
                .font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
                .lineLimit(3)
            Button { store.refreshNow() } label: {
                Text("Try again").font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.yes))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Soft banner for a partial/degraded pass that still produced results.
    private func degradedBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
            Text(message).font(Theme.ui(11, .medium))
            Spacer()
        }
        .foregroundStyle(Color(hex: 0xF59F00))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xF59F00).opacity(0.10)))
    }
}
