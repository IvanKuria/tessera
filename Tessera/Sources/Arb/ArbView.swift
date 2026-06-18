import SwiftUI
import KalshiKit

/// The cross-venue Arbitrage screen (read-only). Clones the `ScannerView` shell:
/// a header with a Simple/Pro mode toggle, a liveness/freshness readout, refresh,
/// and honest loading / empty / error states. There is ONE lane — cross-venue —
/// so no Locks/Edges split; rows reuse `OpportunityRow` / `OpportunityTableRow`.
///
/// Tapping a row opens `ArbDetailPanel` (resolution-mismatch banner, confidence,
/// warnings, and "Open on Kalshi / Polymarket" deep-links). No order placement.
struct ArbView: View {
    @Bindable var store: ArbStore

    enum Mode: String { case simple, pro }
    @AppStorage("arb.mode") private var modeRaw = Mode.simple.rawValue
    @State private var selectedOpp: Opportunity?

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .simple }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .sheet(item: $selectedOpp) { opp in
            ArbDetailPanel(
                opp: opp,
                pair: store.pair(for: opp),
                polymarketSlug: store.polymarketSlug(for: opp),
                onClose: { selectedOpp = nil }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 7) {
                CrossVenueTag()
                Text("Kalshi ↔ Polymarket")
                    .font(Theme.ui(12, .semibold)).foregroundStyle(Theme.textSecondary)
                Text("\(store.opportunities.count)")
                    .font(Theme.num(12, .semibold)).foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Text(phaseLabel).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                } else if let last = store.lastScan {
                    Circle().fill(Theme.textTertiary).frame(width: 7, height: 7)
                    Text(freshnessText(last)).font(Theme.num(11)).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("starting…").font(Theme.ui(11)).foregroundStyle(Theme.textTertiary)
                }
            }

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
        case .idle:               return "scanning…"
        case .discovering:        return "discovering markets…"
        case .matching:           return "matching events…"
        case .confirming(let n):  return "confirming \(n) pairs…"
        case .detecting:          return "pricing…"
        case .degraded(let m):    return m
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
        } else if store.opportunities.isEmpty {
            ScrollView { emptyState }
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
                ForEach(store.opportunities) { opp in
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
                    ForEach(store.opportunities) { opp in
                        OpportunityTableRow(opp: opp) { selectedOpp = opp }
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No cross-venue arbitrage right now — and that's normal.")
                .font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("We match the same real-world event on Kalshi and Polymarket and surface it only when buying both sides clears a profit after each venue's fees. These windows are rare and brief. We keep scanning.")
                .font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            if store.lastScan != nil {
                Text("Last pass: \(store.coverage.kalshiMarkets) Kalshi · \(store.coverage.polymarketMarkets) Polymarket markets → \(store.coverage.matchedPairs) matched events, \(store.coverage.pairsConfirmed) priced. None clear a profit right now.")
                    .font(Theme.num(11)).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 60)
    }

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
                Text("First scan in progress — matching markets across two venues…")
                    .font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 8)
        }
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("CROSS-VENUE").font(Theme.ui(9, .bold)); Spacer(); Text("updated 0s ago").font(Theme.num(10)) }
            Text("A representative market matched across two venues")
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
