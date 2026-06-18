import SwiftUI
import KalshiKit

/// Simple-mode opportunity card. Mirrors `EventCardView` chrome (flat surface,
/// hairline border, hover lift) but leads with the net-of-fee edge hero and the
/// honest framing — fees + depth + annualized are baked into the numbers shown.
struct OpportunityRow: View {
    let opp: Opportunity
    var onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: lane tag + kind + leg count, freshness on the right.
            HStack(alignment: .center, spacing: 8) {
                LaneTag(lane: opp.lane)
                if let cat = opp.category {
                    CategoryIcon(category: cat, size: 18)
                }
                Text(opp.kindLabel)
                    .font(Theme.ui(11, .semibold)).foregroundStyle(Theme.textSecondary)
                Text("· \(opp.legs.count) leg\(opp.legs.count == 1 ? "" : "s")")
                    .font(Theme.ui(11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                FreshnessStamp(age: opp.freshnessAgeSeconds, isNew: opp.freshnessAgeSeconds <= 6)
            }

            Text(opp.title)
                .font(Theme.ui(15.5, .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Economics block. Flag-only edges show the signal, no dollar figure.
            if opp.isFlagOnly {
                HStack(spacing: 12) {
                    Text("Signal — no sized trade")
                        .font(Theme.ui(13, .medium)).foregroundStyle(Theme.textSecondary)
                    if opp.lane == .edge {
                        ConfidenceMeter(score: opp.confidenceDouble)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    NetEdgeHero(cents: opp.netEdgePerContractDouble, lane: opp.lane)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("$\(opp.fitsDollars, specifier: "%.0f") fits")
                            .font(Theme.num(13, .semibold)).foregroundStyle(Theme.text)
                        Text("\(opp.maxContractsInt) contracts at depth")
                            .font(Theme.ui(10)).foregroundStyle(Theme.textTertiary)
                    }
                    if opp.annualizedDouble > 0 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(opp.annualizedDouble, specifier: "%.0f")%")
                                .font(Theme.num(13, .semibold)).foregroundStyle(Theme.text)
                            Text("annualized").font(Theme.ui(10)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if opp.lane == .edge {
                        Spacer(minLength: 0)
                        ConfidenceMeter(score: opp.confidenceDouble)
                    }
                }
            }

            // Warning chips.
            if !opp.warningChips.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(opp.warningChips.enumerated()), id: \.offset) { _, chip in
                        WarningChip(text: chip.text, neutral: chip.neutral)
                    }
                }
            }

            // CTA.
            Button(action: onOpen) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(opp.lane == .lock ? "Review & stake" : "Look closer")
                        .font(Theme.ui(12.5, .semibold))
                }
                .foregroundStyle(opp.lane == .lock ? Theme.yes : Theme.info)
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 13, trailing: 16))
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(hover ? Theme.divider : Theme.border, lineWidth: 1)
        )
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - Pro dense table row

/// Pro-mode dense row: right-aligned `Theme.num` columns for keyboard-friendly
/// scanning. Whole row is tappable; hover paints `Theme.hover`.
struct OpportunityTableRow: View {
    let opp: Opportunity
    var onOpen: () -> Void
    @State private var hover = false

    /// Shared column layout so the header and rows align. (label, width, alignment)
    static let columns: [(String, CGFloat, Alignment)] = [
        ("",          54, .leading),    // lane tag
        ("MARKET",    260, .leading),   // title (flexes via the spacer instead)
        ("NET¢",      62, .trailing),
        ("EDGE%",     62, .trailing),
        ("FITS $",    78, .trailing),
        ("MAX LOSS",  84, .trailing),
        ("ANN%",      62, .trailing),
        ("DTS",       52, .trailing),
        ("AGE",       54, .trailing),
        ("CONF",      52, .trailing),
    ]

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                LaneTag(lane: opp.lane)
                    .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(opp.title)
                        .font(Theme.ui(12.5, .medium)).foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(opp.kindLabel)
                        .font(Theme.ui(9.5)).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                col(opp.isFlagOnly ? "—" : edgeSign + fmt(opp.netEdgePerContractDouble, 1), 62)
                col(opp.isFlagOnly ? "—" : fmtPct(netEdgePctDouble), 62)
                col(opp.isFlagOnly ? "—" : "$\(fmt(opp.fitsDollars, 0))", 78)
                col(opp.isFlagOnly ? "—" : "$\(fmt(opp.maxLossDollarsDouble, 0))", 84)
                col(opp.annualizedDouble > 0 ? fmtPct(opp.annualizedDouble) : "—", 62)
                col(opp.isFlagOnly ? "—" : "\(fmt(opp.daysToSettlementDouble, 1))d", 52)
                col("\(Int(opp.freshnessAgeSeconds))s", 54, ageColor)
                col("\(Int(opp.confidenceDouble * 100))", 52)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(hover ? Theme.hover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var edgeSign: String { opp.lane == .edge ? "~" : "+" }
    private var netEdgePctDouble: Double { NSDecimalNumber(decimal: opp.netEdgePct).doubleValue * 100 }
    private var ageColor: Color {
        opp.freshnessAgeSeconds <= 15 ? Theme.textSecondary
            : opp.freshnessAgeSeconds <= 60 ? Color(hex: 0xF59F00) : Theme.no
    }

    private func fmt(_ v: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", v) }
    private func fmtPct(_ v: Double) -> String { String(format: "%.0f%%", v) }

    private func col(_ text: String, _ width: CGFloat, _ color: Color = Theme.text) -> some View {
        Text(text)
            .font(Theme.num(12)).foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }
}

/// The Pro table header row (sticky look via a divider + subtle background).
struct OpportunityTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(OpportunityTableRow.columns.enumerated()), id: \.offset) { idx, c in
                if idx == 1 {
                    Text(c.0)
                        .frame(maxWidth: .infinity, alignment: c.2)
                } else {
                    Text(c.0)
                        .frame(width: c.1, alignment: c.2)
                }
            }
        }
        .font(Theme.ui(9.5, .semibold))
        .tracking(0.5)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Theme.subtle)
    }
}
