import SwiftUI
import KalshiKit

/// The Scanner screen (Slice 3, read-only). Header carries the lane toggle
/// (Locks·n / Edges·n), the Simple/Pro mode toggle, a live dot + freshness
/// readout, and a Filters stub. Body switches between the Simple list of cards
/// and the Pro dense table, with honest loading / empty / offline / error states.
///
/// Tapping a row's CTA selects an opportunity and presents a simple stub panel
/// (the real execution panel arrives in Slice 5). Appearance follows the system —
/// no `preferredColorScheme` override here.
struct ScannerView: View {
    @Bindable var store: ScannerStore
    var account: AccountStore

    enum Lane: Hashable { case locks, edges }
    enum Mode: String { case simple, pro }

    @State private var lane: Lane = .locks
    @AppStorage("scanner.mode") private var modeRaw = Mode.simple.rawValue
    @State private var selectedOpp: Opportunity?

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .simple }
    private var shownOpps: [Opportunity] { lane == .locks ? store.locks : store.edges }
    private var shownLane: OpportunityLane { lane == .locks ? .lock : .edge }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .sheet(item: $selectedOpp) { opp in
            OpportunityStubPanel(opp: opp) { selectedOpp = nil }
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

            // Liveness + freshness readout.
            HStack(spacing: 8) {
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Text(phaseLabel).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                } else if let last = store.lastScan {
                    LiveDot()
                    Text(freshnessText(last)).font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
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

// MARK: - Stub execution panel (real panel = Slice 5)

/// A minimal preview of the opportunity's legs + net edge, with a "coming soon"
/// note. Replaced by the full dutching calculator / legging modal in Slice 5.
struct OpportunityStubPanel: View {
    let opp: Opportunity
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar.
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    LaneTag(lane: opp.lane)
                    Text(opp.title).font(Theme.ui(16, .semibold)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(opp.kindLabel).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().overlay(Theme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !opp.isFlagOnly {
                        HStack(spacing: 24) {
                            NetEdgeHero(cents: opp.netEdgePerContractDouble, lane: opp.lane)
                            if opp.annualizedDouble > 0 {
                                StatBlock(label: "Annualized", value: String(format: "%.0f%%", opp.annualizedDouble))
                            }
                            StatBlock(label: "Fits", value: String(format: "$%.0f", opp.fitsDollars))
                            if opp.lane == .edge {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Confidence").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                                        .foregroundStyle(Theme.textTertiary)
                                    ConfidenceMeter(score: opp.confidenceDouble)
                                }
                            }
                        }
                    } else {
                        Text("Signal only — no sized trade. This flags a market worth a look, not an arbitrage.")
                            .font(Theme.ui(12.5)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Legs.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEGS").font(Theme.ui(9.5, .semibold)).tracking(0.8)
                            .foregroundStyle(Theme.textTertiary)
                        ForEach(Array(opp.legs.enumerated()), id: \.offset) { _, leg in
                            legRow(leg)
                        }
                    }

                    if !opp.warningChips.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Array(opp.warningChips.enumerated()), id: \.offset) { _, chip in
                                WarningChip(text: chip.text, neutral: chip.neutral)
                            }
                        }
                    }

                    // Coming-soon note.
                    HStack(spacing: 8) {
                        Image(systemName: "hammer.fill").font(.system(size: 11))
                        Text("Staking, the dutching calculator, and one-tap legging are coming soon.")
                            .font(Theme.ui(11.5, .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtle))
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 520)
        .background(Theme.bg)
    }

    private func legRow(_ leg: Leg) -> some View {
        HStack(spacing: 10) {
            Text(leg.side == .yes ? "YES" : "NO")
                .font(Theme.ui(10, .bold))
                .foregroundStyle(leg.side == .yes ? Theme.yes : Theme.no)
                .frame(width: 34, alignment: .leading)
            Text(leg.marketTicker)
                .font(Theme.num(12)).foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            if leg.priceCents > 0 {
                Text("\(leg.priceCents)¢").font(Theme.num(12, .semibold)).foregroundStyle(Theme.text)
            }
            if leg.qty > 0 {
                Text("×\(NSDecimalNumber(decimal: leg.qty).intValue)")
                    .font(Theme.num(11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
    }
}
