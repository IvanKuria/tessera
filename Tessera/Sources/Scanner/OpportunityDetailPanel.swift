import SwiftUI
import KalshiKit

/// Slice 5 — the real execution panel that replaces `OpportunityStubPanel`.
///
/// Serves both Simple and Pro modes from one layout (spec §4):
/// a live-recomputing dutching calculator (STAKE) + RESULT block, the N legs
/// bound as one trade, the warning chips, three actions, and a plain-language
/// "why it's mispriced" explainer. Real order placement is gated behind a
/// mandatory non-atomic legging-risk modal; `Place` is disabled without a
/// connected Kalshi key. Honesty rails: every figure is net of fees, color is
/// always paired with text/glyph, and the word "guaranteed" never describes
/// execution.

// MARK: - Live recompute

/// A pure, value-type recompute of the dutching economics at a chosen stake.
/// Recomputed on the main actor as the user drags the slider / taps steppers —
/// the engine math (`KalshiFees` / `ScannerMath`) is the single source of truth
/// so the panel never shows a number the engine wouldn't stand behind.
struct DutchingResult {
    var contracts: Int
    var totalCostCents: Decimal     // legs' price·qty + fees
    var totalFeesCents: Decimal
    var profitCents: Decimal        // net of fees, at this size
    var roiPct: Double              // profit / cost
    var annualizedPct: Double
    var maxLossCents: Decimal
    var beyondDepth: Bool           // requested stake exceeded fillable cap → clamped

    static let zero = DutchingResult(
        contracts: 0, totalCostCents: 0, totalFeesCents: 0, profitCents: 0,
        roiPct: 0, annualizedPct: 0, maxLossCents: 0, beyondDepth: false
    )
}

private enum DutchingEngine {
    /// Per-contract cash outlay (price only, in cents) summed across legs.
    static func perContractPriceCents(_ opp: Opportunity) -> Decimal {
        opp.legs.reduce(Decimal(0)) { $0 + Decimal($1.priceCents) }
    }

    /// Recompute the full result for a requested dollar stake. Contracts are
    /// floored to whole units and clamped to the engine's fillable cap; if the
    /// request exceeds the cap we clamp and flag `beyondDepth`.
    static func compute(opp: Opportunity, stakeDollars: Double, config: DetectorConfig) -> DutchingResult {
        let perContractPrice = perContractPriceCents(opp)              // cents, price only
        guard perContractPrice > 0 else { return .zero }
        let perContractDollars = NSDecimalNumber(decimal: perContractPrice).doubleValue / 100
        guard perContractDollars > 0 else { return .zero }

        let cap = max(0, opp.maxContractsInt)
        let requested = Int((stakeDollars / perContractDollars).rounded(.down))
        let contracts = max(0, min(requested, cap))
        let beyond = requested > cap && cap > 0

        guard contracts > 0 else {
            return DutchingResult(
                contracts: 0, totalCostCents: 0, totalFeesCents: 0, profitCents: 0,
                roiPct: 0, annualizedPct: 0, maxLossCents: 0, beyondDepth: beyond
            )
        }

        let q = Decimal(contracts)

        // Recompute fees live from the engine so the displayed total is honest.
        var totalFees = Decimal(0)
        for leg in opp.legs {
            let rate = ScannerMath.feeRate(seriesTicker: opp.seriesTicker, role: config.feeRole, config: config)
            totalFees += ScannerMath.feeCents(contracts: q, priceCents: leg.priceCents, rate: rate)
        }

        let priceOutlay = perContractPrice * q
        let totalCost = priceOutlay + totalFees

        // Gross payout per set: net-edge-per-contract already nets fees on the
        // engine's modelled size, so reconstruct gross from price + per-contract
        // gross. grossPerContract = netPerContract + (engineFee / engineQty).
        // Simpler + exact: profit = grossEdge(at size) − fees(at size).
        // gross per set (cents) = perContractGross; derive from opp.netEdgePerContract + its fee share.
        let grossPerContract = grossPerContractCents(opp)
        let profit = grossPerContract * q - totalFees

        let roi = totalCost > 0 ? NSDecimalNumber(decimal: profit / totalCost).doubleValue : 0
        let netPct = totalCost > 0 ? profit / totalCost : 0
        let annual = ScannerMath.annualizedPct(netEdgePct: netPct, days: opp.daysToSettlement)

        // Max loss: a lock is provable ($0); an edge carries the engine's legged-out figure,
        // scaled to the chosen size.
        let maxLoss: Decimal
        if opp.lane == .lock {
            maxLoss = 0
        } else if cap > 0 {
            let perContractLoss = opp.maxLossIfLeggedOutCents / Decimal(cap)
            maxLoss = perContractLoss * q
        } else {
            maxLoss = opp.maxLossIfLeggedOutCents
        }

        return DutchingResult(
            contracts: contracts, totalCostCents: totalCost, totalFeesCents: totalFees,
            profitCents: profit, roiPct: roi,
            annualizedPct: NSDecimalNumber(decimal: annual).doubleValue,
            maxLossCents: maxLoss, beyondDepth: beyond
        )
    }

    /// Per-contract GROSS payout edge (before fees), reconstructed from the engine's
    /// modelled net + the fee it charged at that modelled size.
    static func grossPerContractCents(_ opp: Opportunity) -> Decimal {
        guard let q = opp.legs.first?.qty, q > 0 else { return opp.netEdgePerContractCents }
        let modelledFeePerContract = opp.totalFeesCents / q
        return opp.netEdgePerContractCents + modelledFeePerContract
    }
}

// MARK: - Glossary tooltip

/// An ambient `ⓘ` info button that reveals a plain-language definition in a popover.
struct GlossaryTip: View {
    let title: String
    let detail: String
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 240)
        }
    }
}

// MARK: - Bound legs group (Task 15)

/// The N legs inside ONE bordered container with a left "tie-bar" — a visual
/// rule spanning all legs that frames them as a single bound trade. Each leg
/// row shows a dot + ticker + side tag + depth status + qty + price/fee.
struct BoundLegsGroup: View {
    let opp: Opportunity
    let contracts: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("BOUND LEGS").font(Theme.ui(9.5, .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Text("placed as one trade").font(Theme.ui(10)).foregroundStyle(Theme.textTertiary)
                GlossaryTip(title: "Dutching",
                            detail: "Buying every leg of a mutually-exclusive set so that whichever outcome resolves, the combined payout exceeds your total cost. These legs work only together.")
            }

            HStack(alignment: .top, spacing: 10) {
                // Tie-bar: a 2pt rule spanning all legs.
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.divider)
                    .frame(width: 2)
                VStack(spacing: 0) {
                    ForEach(Array(opp.legs.enumerated()), id: \.offset) { idx, leg in
                        if idx > 0 { Divider().overlay(Theme.border) }
                        legRow(leg)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func legRow(_ leg: Leg) -> some View {
        let thin = NSDecimalNumber(decimal: leg.depthAvailable).doubleValue < 5
        let feeC = liveFeeCents(leg)
        return HStack(spacing: 10) {
            Circle()
                .fill((leg.side == .yes ? Theme.yes : Theme.no).opacity(0.85))
                .frame(width: 8, height: 8)

            Text(leg.marketTicker)
                .font(Theme.num(11.5)).foregroundStyle(Theme.text)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)

            Text(leg.side == .yes ? "YES" : "NO")
                .font(Theme.ui(9.5, .bold))
                .foregroundStyle(leg.side == .yes ? Theme.yes : Theme.no)

            // Depth status: ✓ or ⚠ thin (always paired with text).
            HStack(spacing: 2) {
                Image(systemName: thin ? "exclamationmark.triangle.fill" : "checkmark")
                    .font(.system(size: 7.5, weight: .bold))
                Text(thin ? "thin" : "depth")
                    .font(Theme.ui(9))
            }
            .foregroundStyle(thin ? Color(hex: 0xF59F00) : Theme.textTertiary)

            Spacer(minLength: 6)

            if contracts > 0 {
                Text("×\(contracts)").font(Theme.num(10.5)).foregroundStyle(Theme.textTertiary)
            }
            Text("\(leg.priceCents)¢").font(Theme.num(11.5, .semibold)).foregroundStyle(Theme.text)
            Text("+\(feeC)¢ fee").font(Theme.num(9.5)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    /// Per-leg fee at the current contract count (engine math); 0 when unsized.
    private func liveFeeCents(_ leg: Leg) -> Int {
        guard contracts > 0 else { return 0 }
        let rate = ScannerMath.feeRate(seriesTicker: opp.seriesTicker, role: .taker, config: DetectorConfig())
        let f = ScannerMath.feeCents(contracts: Decimal(contracts), priceCents: leg.priceCents, rate: rate)
        return NSDecimalNumber(decimal: f).intValue
    }
}

