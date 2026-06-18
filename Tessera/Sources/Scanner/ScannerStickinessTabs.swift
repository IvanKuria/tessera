import SwiftUI
import KalshiKit

// MARK: - Shared "Paper — no real money" banner

/// The non-negotiable honesty banner shown anywhere paper figures appear. Carries
/// the start date so cumulative numbers can never be mistaken for realised money.
private struct PaperBanner: View {
    let startedAt: Date?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill").font(.system(size: 11))
                .foregroundStyle(Theme.info)
            Text(label).font(Theme.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.info.opacity(0.08)))
    }

    private var label: String {
        guard let startedAt else { return "Paper — no real money. Tracks forward only." }
        let f = DateFormatter(); f.dateStyle = .medium
        return "Paper — no real money, started \(f.string(from: startedAt)). Forward only — never hypothetical."
    }
}

// MARK: - Watching tab

/// Tracked opportunities with honest fate labels: still live (with the current
/// net edge) or closed (left the scan). No projections, no "would've".
struct WatchingTab: View {
    @Bindable var store: ScannerStore
    var onOpen: (Opportunity) -> Void

    private var trackedIDs: [String] { Array(store.tracked.ids).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("You're alerted on these regardless of the global threshold (cooldown still applies).")
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)

                if trackedIDs.isEmpty {
                    emptyState
                } else {
                    ForEach(trackedIDs, id: \.self) { id in
                        row(id: id, opp: store.oppsByID[id])
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func row(id: String, opp: Opportunity?) -> some View {
        let isLive = opp != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let opp { LaneTag(lane: opp.lane) }
                Spacer()
                fateLabel(opp: opp)
                Button {
                    store.tracked.untrack(id)
                } label: {
                    Image(systemName: "bell.slash").font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Stop tracking")
            }
            Text(opp?.title ?? id)
                .font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let opp {
                HStack(spacing: 12) {
                    Text(String(format: "net edge now %+.1f¢/contract",
                                NSDecimalNumber(decimal: opp.netEdgePerContractCents).doubleValue))
                        .font(Theme.num(12, .semibold))
                        .foregroundStyle(opp.netEdgeCents > 0 ? Theme.yes : Theme.textSecondary)
                    FreshnessStamp(age: opp.freshnessAgeSeconds)
                }
                Button { onOpen(opp) } label: {
                    Text("Open").font(Theme.ui(12, .semibold)).foregroundStyle(Theme.info)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .opacity(isLive ? 1 : 0.7)
    }

    private func fateLabel(opp: Opportunity?) -> some View {
        let live = opp != nil
        return HStack(spacing: 4) {
            Image(systemName: live ? "dot.radiowaves.left.and.right" : "moon.zzz")
                .font(.system(size: 9, weight: .semibold))
            Text(live ? "still live" : "closed")
                .font(Theme.ui(10, .semibold))
        }
        .foregroundStyle(live ? Theme.yes : Theme.textTertiary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill((live ? Theme.yes : Theme.textTertiary).opacity(0.12)))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell")
                .font(.system(size: 26, weight: .light)).foregroundStyle(Theme.textTertiary)
            Text("Nothing tracked yet").font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)
            Text("Open an opportunity and tap \u{201C}Track & alert me\u{201D} to watch its fate here.")
                .font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

// MARK: - Paper P&L tab

/// The forward-only paper ledger. Rewards edge found + consistency, NOT trade
/// count. Always banner-labelled "Paper — no real money".
struct PaperPnLTab: View {
    @Bindable var paper: PaperLedger

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PaperBanner(startedAt: paper.startedAt)

                statsRow

                if paper.entries.isEmpty {
                    emptyState
                } else {
                    Text("ENTRIES").font(Theme.ui(9.5, .semibold)).tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(paper.entries.sorted { $0.openedAt > $1.openedAt }) { entry in
                        entryRow(entry)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            StatBlock(label: "Cumulative net (paper)",
                      value: money(paper.cumulativeNetDollars),
                      valueColor: paper.cumulativeNetDollars >= 0 ? Theme.yes : Theme.no)
            StatBlock(label: "Avg edge found",
                      value: String(format: "%.1f¢", paper.averageEdgeCents))
            StatBlock(label: "Provable locks",
                      value: String(format: "%d (%.0f%%)", paper.lockCount, paper.lockShare * 100))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func entryRow(_ entry: PaperEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.kindLabel.uppercased())
                        .font(Theme.ui(9, .bold)).tracking(0.6)
                        .foregroundStyle(entry.lane == .lock ? Theme.yes : Theme.info)
                    Text(dateLabel(entry.openedAt))
                        .font(Theme.num(10)).foregroundStyle(Theme.textTertiary)
                }
                Text(entry.title).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(String(format: "%d contracts · %.0f¢ edge at open · stake $%.0f",
                            entry.contracts, entry.netEdgeCentsAtOpen, entry.stakeDollars))
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(entry.capturedNetDollars))
                    .font(Theme.num(13, .semibold))
                    .foregroundStyle(entry.capturedNetDollars >= 0 ? Theme.yes : Theme.no)
                Text("net at open").font(Theme.ui(9)).foregroundStyle(Theme.textTertiary)
            }
            Button { paper.remove(entry) } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain).help("Remove entry")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 26, weight: .light)).foregroundStyle(Theme.textTertiary)
            Text("No paper trades yet").font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)
            Text("Paper-trade an opportunity to start a forward log. We record the edge you found — never a hypothetical \u{201C}you would have made.\u{201D}")
                .font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: d)
    }
    private func money(_ d: Double) -> String { String(format: d < 0 ? "−$%.2f" : "$%.2f", abs(d)) }
}

// MARK: - Digest tab

/// Opt-in daily "Top mispricings" digest: best Locks by net edge + highest-
/// confidence Edges, each with how long it has survived. One notification/day max.
struct DigestTab: View {
    @Bindable var store: ScannerStore
    @State private var digest: ScannerDigest?

    private var current: ScannerDigest { digest ?? store.previewDigest() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                optInCard

                let d = current
                if d.isEmpty {
                    emptyState
                } else {
                    if !d.locks.isEmpty { section("Top locks (by net edge)", d.locks) }
                    if !d.edges.isEmpty { section("Top edges (by confidence)", d.edges) }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .onAppear { digest = store.previewDigest() }
    }

    private var optInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { store.settings.digestEnabled },
                set: { var s = store.settings; s.digestEnabled = $0; store.updateSettings(s) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me a daily digest").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.text)
                    Text("One notification per day, max — the day's top mispricings. Opt-in, no hype.")
                        .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.yes)

            Button {
                digest = store.previewDigest()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                    Text("Generate today's digest").font(Theme.ui(12, .semibold))
                }
                .foregroundStyle(Theme.info)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.info.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func section(_ title: String, _ items: [DigestItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Theme.ui(9.5, .semibold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            ForEach(items) { item in itemRow(item) }
        }
    }

    private func itemRow(_ item: DigestItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(item.kindLabel).font(Theme.ui(10)).foregroundStyle(Theme.textSecondary)
                    Text("· \(item.survivalLabel)").font(Theme.ui(10)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if item.lane == .lock {
                    Text(String(format: "%.0f¢", item.netEdgeCents))
                        .font(Theme.num(13, .semibold)).foregroundStyle(Theme.yes)
                    Text("net/contract").font(Theme.ui(9)).foregroundStyle(Theme.textTertiary)
                } else {
                    Text(String(format: "%d%%", Int(item.confidence * 100)))
                        .font(Theme.num(13, .semibold)).foregroundStyle(Theme.info)
                    Text("confidence").font(Theme.ui(9)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light)).foregroundStyle(Theme.textTertiary)
            Text("No mispricings to summarise yet").font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)
            Text("Once a scan surfaces actionable locks or edges, the day's best appear here.")
                .font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
