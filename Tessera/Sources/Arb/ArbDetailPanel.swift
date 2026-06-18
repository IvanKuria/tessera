import SwiftUI
import AppKit
import KalshiKit
import ArbEngine

/// The read-only detail panel for a cross-venue arbitrage opportunity.
///
/// Reuses the Scanner's `BoundLegsGroup` (now carrying a per-leg venue badge),
/// the net-edge / result styling, the `ConfidenceMeter`, and the `WarningChip`
/// flow — then adds the cross-venue specifics:
///  - a prominent **resolution-mismatch banner** showing BOTH venues' settlement
///    texts side by side (the #1 cross-venue killer), shown when the matcher
///    flagged a mismatch;
///  - a **match-confidence** readout;
///  - the cross-venue / legging / USDC warning chips;
///  - **"Open on Kalshi"** / **"Open on Polymarket"** deep-link buttons.
///
/// There is NO order placement here — cross-venue fills are non-atomic and
/// Polymarket needs a wallet; we surface and link out, nothing more. Honesty
/// rails: every figure is net of fees, the word "guaranteed" never appears, and
/// color is always paired with text.
struct ArbDetailPanel: View {
    let opp: Opportunity
    /// The matched pair behind this opportunity (resolution texts + PM slug).
    let pair: MatchedPair?
    /// The Polymarket deep-link slug (from the store's side map), if known.
    let polymarketSlug: String?
    var onClose: () -> Void

    private var hasMismatch: Bool {
        opp.warnings.contains { if case .resolutionMismatch = $0 { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if hasMismatch { resolutionMismatchBanner }

                    resultBlock

                    BoundLegsGroup(opp: opp, contracts: opp.maxContractsInt)

                    confidenceBlock

                    if !opp.warningChips.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Array(opp.warningChips.enumerated()), id: \.offset) { _, chip in
                                WarningChip(text: chip.text, neutral: chip.neutral)
                            }
                        }
                    }

                    if !hasMismatch { resolutionTextsBlock }

                    deepLinkButtons

                    readOnlyNote
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 660)
        .background(Theme.bg)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    CrossVenueTag()
                    Text("\(opp.legs.count) legs across two venues")
                        .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)
                }
                Text(opp.title).font(Theme.ui(16, .semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                FreshnessStamp(age: opp.freshnessAgeSeconds)
            }
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: Resolution-mismatch banner

    private var resolutionMismatchBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14)).foregroundStyle(warningAmberLocal)
                Text("Resolution criteria may differ")
                    .font(Theme.ui(13.5, .semibold)).foregroundStyle(Theme.text)
            }
            Text("These two markets matched on their question, but their settlement rules may not be identical. Cross-venue arbitrage breaks when the venues resolve the same event differently — verify the settlement rules match before trading.")
                .font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                resolutionColumn(venue: .kalshi, text: pair?.kalshiRules)
                Divider().frame(height: 110).overlay(Theme.border)
                resolutionColumn(venue: .polymarket, text: pair?.pmResolution)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(warningAmberLocal.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(warningAmberLocal.opacity(0.35), lineWidth: 1))
    }

    private func resolutionColumn(venue: Venue, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VenueBadge(venue: venue)
            Text(text?.isEmpty == false ? text! : "No settlement text published.")
                .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Resolution texts (when NOT a flagged mismatch — still worth showing)

    @ViewBuilder private var resolutionTextsBlock: some View {
        if pair?.kalshiRules?.isEmpty == false || pair?.pmResolution?.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("SETTLEMENT RULES").font(Theme.ui(9.5, .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                HStack(alignment: .top, spacing: 12) {
                    resolutionColumn(venue: .kalshi, text: pair?.kalshiRules)
                    Divider().frame(height: 80).overlay(Theme.border)
                    resolutionColumn(venue: .polymarket, text: pair?.pmResolution)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.subtle))
        }
    }

    // MARK: Result block (net-of-fee edge first)

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            NetEdgeHero(cents: opp.netEdgePerContractDouble, lane: .edge)

            HStack(alignment: .top, spacing: 18) {
                StatBlock(label: "Net profit at depth", value: money(opp.netEdgeCents), valueColor: Theme.info)
                StatBlock(label: "Capital", value: money(opp.capitalRequiredCents))
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f%%", opp.annualizedDouble))
                        .font(Theme.num(14, .semibold)).foregroundStyle(Theme.text)
                    Text("ANNUALIZED").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                    Text("◷ \(daysLabel) to settle").font(Theme.ui(9)).foregroundStyle(Theme.textTertiary)
                }
                StatBlock(label: "Fits", value: "$\(Int(opp.fitsDollars))")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var confidenceBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("MATCH CONFIDENCE").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                GlossaryTip(title: "Match confidence",
                            detail: "How sure we are these two markets describe the same real-world event, blended from on-device semantic similarity, shared words, and matching dates/entities. Lower confidence means verify the legs before trading.")
            }
            ConfidenceMeter(score: opp.confidenceDouble)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Deep-link buttons (read-only — open each venue, no execution)

    private var deepLinkButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                deepLinkButton(label: "Open on Kalshi", tint: Theme.yes, url: kalshiURL)
                deepLinkButton(label: "Open on Polymarket", tint: VenueBadge.polymarketViolet, url: polymarketURL)
            }
        }
    }

    private func deepLinkButton(label: String, tint: Color, url: URL?) -> some View {
        Button { if let url { NSWorkspace.shared.open(url) } } label: {
            HStack(spacing: 6) {
                Text(label).font(Theme.ui(12.5, .semibold))
                Image(systemName: "arrow.up.right.square").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11).stroke(tint, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .opacity(url == nil ? 0.5 : 1)
    }

    /// Kalshi leg deep-link: `https://kalshi.com/markets/<ticker>`.
    private var kalshiURL: URL? {
        let ticker = opp.legs.first { $0.venue == .kalshi }?.marketTicker ?? opp.eventTicker
        return URL(string: "https://kalshi.com/markets/\(ticker)")
    }

    /// Polymarket leg deep-link: `https://polymarket.com/event/<slug>`. The slug
    /// comes from the stored matched pair (the leg only carries the market id).
    private var polymarketURL: URL? {
        guard let slug = polymarketSlug, !slug.isEmpty else { return nil }
        return URL(string: "https://polymarket.com/event/\(slug)")
    }

    private var readOnlyNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Text("Read-only. We surface the opportunity and link to each venue — we never place orders. Cross-venue legs fill separately (non-atomic), Polymarket needs a USDC wallet, and the two exchanges settle independently.")
                .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
    }

    // MARK: Helpers

    private var daysLabel: String {
        let d = opp.daysToSettlementDouble
        if d < 1 { return "<1d" }
        return "\(Int(d.rounded()))d"
    }

    private func money(_ cents: Decimal) -> String {
        let d = NSDecimalNumber(decimal: cents).doubleValue / 100
        return String(format: "$%.2f", d)
    }

    private let warningAmberLocal = Color(hex: 0xF59F00)
}

// MARK: - Cross-venue tag

/// A small pill labeling a cross-venue arbitrage opportunity in the detail header.
struct CrossVenueTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 8, weight: .bold))
            Text("CROSS-VENUE").font(Theme.ui(9, .bold)).tracking(0.6)
        }
        .foregroundStyle(Theme.info)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(Capsule().fill(Theme.info.opacity(0.12)))
    }
}
