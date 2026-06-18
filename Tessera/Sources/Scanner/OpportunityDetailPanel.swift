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

            // Venue badge — only for cross-venue arb legs (venue set); the
            // single-venue Scanner leaves `venue == nil` so nothing renders.
            if let venue = leg.venue {
                VenueBadge(venue: venue)
            }

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

// MARK: - Why-mispriced explainer (Task 16)

/// A collapsible, plain-language explanation of why this opportunity exists, with
/// a worked $-example computed from the user's current stake and an honest ceiling.
struct WhyMispricedExplainer: View {
    let opp: Opportunity
    let result: DutchingResult
    @State private var expanded: Bool

    init(opp: Opportunity, result: DutchingResult, startExpanded: Bool) {
        self.opp = opp
        self.result = result
        _expanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 11))
                        .foregroundStyle(Theme.info)
                    Text("Why is this mispriced?").font(Theme.ui(12.5, .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(reason).font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if result.contracts > 0 {
                        workedExample
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xF59F00))
                        Text(honestCeiling).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.subtle))
    }

    private var workedExample: some View {
        let cost = dollars(result.totalCostCents)
        let profit = dollars(result.profitCents)
        return VStack(alignment: .leading, spacing: 3) {
            Text("Worked example").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            Text("Stake \(money(cost)) across \(opp.legs.count) legs (\(result.contracts) contracts each). "
                 + (opp.lane == .lock
                    ? "Whichever outcome wins, you collect more than you paid — net \(money(profit)) after fees."
                    : "If the price relationship holds to settlement, you net about \(money(profit)) after fees."))
                .font(Theme.ui(11.5)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
    }

    private var reason: String {
        switch opp.kind {
        case .lock(.multiOutcomeUnderround):
            return "This is a mutually-exclusive event: exactly one outcome will resolve YES. Right now the cost to buy YES on every outcome adds up to less than the \u{0024}1 one of them is guaranteed to pay — even after fees. That gap is a provable lock."
        case .lock(.multiOutcomeOverround):
            return "Exactly one outcome resolves YES, so all but one resolve NO. Buying NO on every outcome costs less than the guaranteed NO payouts — after fees, that difference is yours regardless of which outcome wins."
        case .edge(.ladderMonotonicity):
            return "Two rungs of the same threshold ladder are priced inconsistently: a looser threshold is cheaper than it logically should be versus a tighter one. Buying the cheap looser YES and the tighter NO captures the slip — but it's only an edge, not a provable lock, because depth can vanish."
        case .edge(.wideSpread):
            return "The gap between the best buy and sell price is unusually wide. That's a signal the quote may be stale or lightly traded — worth a look, not a sized trade."
        case .edge(.staleQuote):
            return "This quote hasn't moved in a while. It may be lagging the true market — a signal to watch, not an arbitrage."
        case .edge(.crossVenueArb):
            return "The same real-world event is priced differently on Kalshi and Polymarket: buying YES on the cheaper venue and NO on the other covers both outcomes for less than the \u{0024}1 payout, even after each venue's fees. The legs settle on independent exchanges, so verify the resolution rules match before trading."
        }
    }

    private var honestCeiling: String {
        var notes: [String] = []
        if opp.maxContractsInt < 25 {
            notes.append("depth is thin — only ~\(opp.maxContractsInt) contracts fit before the edge erodes")
        }
        if opp.fitsDollars < 50 {
            notes.append("this is small money (≈\(money(opp.fitsDollars)) deployable)")
        }
        notes.append("opportunities like this can disappear in seconds as the book moves")
        return "Honest ceiling: " + notes.joined(separator: "; ") + "."
    }

    private func dollars(_ cents: Decimal) -> Double { NSDecimalNumber(decimal: cents).doubleValue / 100 }
    private func money(_ d: Double) -> String { String(format: "$%.2f", d) }
}

// MARK: - Legging-risk modal (Task 17)

/// A mandatory, checkbox-gated confirmation before any real multi-leg order.
/// Kalshi has no atomic multi-leg fill, so the user must acknowledge they can be
/// "legged out". Confirm is disabled until the box is ticked. Never says
/// "guaranteed".
struct LeggingRiskModal: View {
    let opp: Opportunity
    let result: DutchingResult
    let envBadge: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var acknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16)).foregroundStyle(Color(hex: 0xF59F00))
                Text("These legs are NOT placed atomically")
                    .font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                envChip
            }

            Text("Kalshi fills each leg as a SEPARATE order. If the market moves between fills, one leg can fill and another fail — leaving you holding an unbalanced position. This is called being \u{201C}legged out.\u{201D}")
                .font(Theme.ui(12.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line").font(.system(size: 11))
                Text("We place the thinnest-depth leg first to minimise this, but it can still happen.")
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.textSecondary)
            }

            // Worst-case line — never "guaranteed".
            HStack {
                Text("Worst case if legged out")
                    .font(Theme.ui(11.5, .medium)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(worstCase).font(Theme.num(13, .semibold)).foregroundStyle(Theme.no)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.no.opacity(0.08)))

            Button { acknowledged.toggle() } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15)).foregroundStyle(acknowledged ? Theme.yes : Theme.textTertiary)
                    Text("I understand these are separate orders and I can be legged out.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button { onCancel() } label: {
                    Text("Cancel").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button { onConfirm() } label: {
                    Text("Place \(opp.legs.count) legs")
                        .font(Theme.ui(13, .semibold)).foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(acknowledged ? Theme.yes : Theme.textTertiary))
                }
                .buttonStyle(.plain)
                .disabled(!acknowledged)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.bg)
    }

    private var envChip: some View {
        Text(envBadge)
            .font(Theme.ui(9.5, .bold)).tracking(0.6)
            .foregroundStyle(envBadge == "PROD" ? Theme.no : Theme.info)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill((envBadge == "PROD" ? Theme.no : Theme.info).opacity(0.14)))
    }

    private var worstCase: String {
        let d = NSDecimalNumber(decimal: result.maxLossCents).doubleValue / 100
        if opp.lane == .lock && d <= 0 {
            return "minimal (provable lock)"
        }
        return String(format: "−$%.2f", d)
    }
}

// MARK: - Placement state

private enum LegPlacementStatus: Equatable {
    case pending, placing, placed, failed(String)
}

@MainActor
private final class PlacementModel: ObservableObject {
    @Published var statuses: [String: LegPlacementStatus] = [:]
    @Published var inFlight = false
    @Published var leggedOutMessage: String?

    func reset(_ legs: [Leg]) {
        statuses = Dictionary(uniqueKeysWithValues: legs.map { ($0.marketTicker, .pending) })
        leggedOutMessage = nil
    }
}

// MARK: - The panel (Task 16 + 17)

struct OpportunityDetailPanel: View {
    let opp: Opportunity
    var account: AccountStore
    var paper: PaperLedger
    @Bindable var tracked: TrackedStore
    var onClose: () -> Void

    @State private var stakeDollars: Double
    @State private var showLeggingModal = false
    @State private var paperConfirmed = false
    @StateObject private var placement = PlacementModel()

    private let config = DetectorConfig()

    init(opp: Opportunity, account: AccountStore, paper: PaperLedger, tracked: TrackedStore, onClose: @escaping () -> Void) {
        self.opp = opp
        self.account = account
        self.paper = paper
        self.tracked = tracked
        self.onClose = onClose
        // Friendly default: min($50, fillable cap).
        _stakeDollars = State(initialValue: min(50, max(0, opp.fitsDollars)))
    }

    private var isTracked: Bool { tracked.isTracked(opp.id) }

    private var result: DutchingResult {
        DutchingEngine.compute(opp: opp, stakeDollars: stakeDollars, config: config)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if opp.isFlagOnly {
                        flagOnlyNote
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            stakeBlock
                            resultBlock
                        }
                        BoundLegsGroup(opp: opp, contracts: result.contracts)
                    }

                    if !opp.warningChips.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Array(opp.warningChips.enumerated()), id: \.offset) { _, chip in
                                WarningChip(text: chip.text, neutral: chip.neutral)
                            }
                        }
                    }

                    if !opp.isFlagOnly { actionButtons }

                    WhyMispricedExplainer(opp: opp, result: result, startExpanded: true)
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 640)
        .background(Theme.bg)
        .sheet(isPresented: $showLeggingModal) {
            LeggingRiskModal(
                opp: opp, result: result, envBadge: account.env.badge,
                onConfirm: { showLeggingModal = false; Task { await placeAllLegs() } },
                onCancel: { showLeggingModal = false }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LaneTag(lane: opp.lane)
                    Text("\(opp.legs.count) legs bound as one trade")
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

    // MARK: STAKE block (calculator)

    private var stakeBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("STAKE").font(Theme.ui(9.5, .semibold)).tracking(0.8).foregroundStyle(Theme.textTertiary)
                GlossaryTip(title: "Net edge",
                            detail: "Your profit after Kalshi's trading fees and the achievable order-book price — not the headline gap. We always lead with this.")
            }

            HStack(spacing: 8) {
                stepper("minus") { stakeDollars = max(0, stakeDollars - 5) }
                Text(String(format: "$%.0f", stakeDollars))
                    .font(Theme.num(22, .semibold)).foregroundStyle(Theme.text)
                    .frame(minWidth: 64)
                stepper("plus") { stakeDollars = min(opp.fitsDollars, stakeDollars + 5) }
            }

            // Slider capped at the fillable depth, with the cap marked.
            VStack(alignment: .leading, spacing: 3) {
                Slider(value: $stakeDollars, in: 0...max(1, opp.fitsDollars))
                    .tint(Theme.yes)
                HStack {
                    Text("$0").font(Theme.num(9)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(String(format: "cap $%.0f", opp.fitsDollars))
                        .font(Theme.num(9)).foregroundStyle(Theme.textTertiary)
                }
            }

            Text("\(result.contracts) contracts × \(opp.legs.count) legs")
                .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)

            if result.beyondDepth {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text("beyond depth — edge turns negative")
                        .font(Theme.ui(10, .medium))
                }
                .foregroundStyle(Theme.no)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func stepper(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.subtle).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: RESULT block

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Text("RESULT").font(Theme.ui(9.5, .semibold)).tracking(0.8).foregroundStyle(Theme.textTertiary)
                GlossaryTip(title: "Annualized",
                            detail: "Your ROI scaled to a yearly rate, so a 1% edge that settles in 3 days is comparable to one that takes 6 months. Capital is locked until settlement.")
            }

            HStack(alignment: .top, spacing: 18) {
                StatBlock(
                    label: opp.lane == .lock ? "Profit (net)" : "Est. profit if it holds",
                    value: money(result.profitCents),
                    valueColor: opp.lane == .lock ? Theme.yes : Theme.info
                )
                StatBlock(label: "ROI", value: String(format: "%.1f%%", result.roiPct * 100))
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f%%", result.annualizedPct))
                        .font(Theme.num(14, .semibold)).foregroundStyle(Theme.text)
                    HStack(spacing: 3) {
                        Text("ANNUALIZED").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text("◷ \(daysLabel) to settle").font(Theme.ui(9)).foregroundStyle(Theme.textTertiary)
                }
                StatBlock(label: "Max loss", value: maxLossLabel,
                          valueColor: opp.lane == .lock ? Theme.textSecondary : Theme.no)
            }

            if opp.lane == .edge {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONFIDENCE").font(Theme.ui(9.5, .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                    ConfidenceMeter(score: opp.confidenceDouble)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var maxLossLabel: String {
        if opp.lane == .lock { return "$0 (provable lock)" }
        return money(result.maxLossCents, negative: true)
    }

    private var daysLabel: String {
        let d = opp.daysToSettlementDouble
        if d < 1 { return "<1d" }
        return "\(Int(d.rounded()))d"
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            placeAllButton

            HStack(spacing: 10) {
                Button {
                    paper.record(opp, stakeDollars: stakeDollars, contracts: result.contracts)
                    paperConfirmed = true
                } label: {
                    Text(paperConfirmed ? "Paper-trade recorded" : "Paper-trade this")
                        .font(Theme.ui(12.5, .semibold))
                        .foregroundStyle(paperConfirmed ? Theme.yes : Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(paperConfirmed ? Theme.yes : Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(result.contracts < 1 || paperConfirmed)
                .help("Logs this opportunity to your forward paper ledger — no real money")

                Button { tracked.toggle(opp.id) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isTracked ? "bell.fill" : "bell").font(.system(size: 10))
                        Text(isTracked ? "Tracking" : "Track & alert me")
                    }
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(isTracked ? Theme.info : Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(isTracked ? Theme.info : Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(isTracked ? "We alert you on this regardless of the global threshold" : "Get a notification when this opportunity crosses up into actionable")
            }

            if paperConfirmed {
                stubNote("Recorded to your paper ledger — forward only, no real money. See the Paper P&L tab.")
            }
            if isTracked {
                stubNote("Tracking — you'll be alerted on a fresh actionable crossing (cooldown applies). See the Watching tab.")
            }

            placementProgress
        }
    }

    private var placeAllButton: some View {
        Button {
            if account.isSignedIn { showLeggingModal = true }
        } label: {
            HStack(spacing: 6) {
                Text("Place all \(opp.legs.count) legs")
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                if account.isSignedIn {
                    Text(account.env.badge)
                        .font(Theme.ui(9, .bold)).tracking(0.5)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.onAccent.opacity(0.2)))
                }
            }
            .font(Theme.ui(13.5, .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 11).fill(account.isSignedIn ? Theme.yes : Theme.textTertiary))
        }
        .buttonStyle(.plain)
        .disabled(!account.isSignedIn || result.contracts < 1 || placement.inFlight)
        .help(account.isSignedIn ? "Place each leg, thinnest depth first" : "Connect your Kalshi key")
    }

    @ViewBuilder private var placementProgress: some View {
        if !placement.statuses.isEmpty && (placement.inFlight || placement.statuses.values.contains { $0 != .pending }) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sortedLegsThinnestFirst, id: \.marketTicker) { leg in
                    HStack(spacing: 8) {
                        statusGlyph(placement.statuses[leg.marketTicker] ?? .pending)
                        Text(leg.marketTicker).font(Theme.num(11)).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(statusText(placement.statuses[leg.marketTicker] ?? .pending))
                            .font(Theme.ui(10.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let msg = placement.leggedOutMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 11))
                        Text(msg).font(Theme.ui(11, .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.no)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.no.opacity(0.08)))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 11).fill(Theme.subtle))
        }
    }

    @ViewBuilder private func statusGlyph(_ s: LegPlacementStatus) -> some View {
        switch s {
        case .pending: Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        case .placing: ProgressView().controlSize(.small)
        case .placed:  Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.yes)
        case .failed:  Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.no)
        }
    }

    private func statusText(_ s: LegPlacementStatus) -> String {
        switch s {
        case .pending: return "queued"
        case .placing: return "placing…"
        case .placed:  return "placed"
        case .failed(let m): return m
        }
    }

    private func stubNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 10))
            Text(text).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
    }

    private var flagOnlyNote: some View {
        Text("Signal only — no sized trade. This flags a market worth a look, not an arbitrage.")
            .font(Theme.ui(12.5)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Order placement (Task 17)

    /// Legs sequenced thinnest-depth first to minimise legging-out exposure.
    private var sortedLegsThinnestFirst: [Leg] {
        opp.legs.sorted {
            NSDecimalNumber(decimal: $0.depthAvailable).doubleValue
                < NSDecimalNumber(decimal: $1.depthAvailable).doubleValue
        }
    }

    /// Places each leg as a separate order, stopping on the first failure and
    /// surfacing an honest "legged out" warning. Real money only; gated by the
    /// legging modal and a connected key.
    private func placeAllLegs() async {
        let legs = sortedLegsThinnestFirst
        let count = result.contracts
        guard count >= 1, account.isSignedIn else { return }

        placement.reset(legs)
        placement.inFlight = true
        defer { placement.inFlight = false }

        for (idx, leg) in legs.enumerated() {
            placement.statuses[leg.marketTicker] = .placing
            let clientOrderId = "scanner-\(opp.id)-\(leg.marketTicker)-\(leg.side.rawValue)-\(count)"
            let result = await account.placeOrder(
                marketTicker: leg.marketTicker,
                action: .buy,
                side: leg.side == .yes ? .yes : .no,
                count: count,
                limitCents: leg.priceCents,
                clientOrderId: clientOrderId
            )
            switch result {
            case .success:
                placement.statuses[leg.marketTicker] = .placed
            case .failure(let error):
                placement.statuses[leg.marketTicker] = .failed("failed")
                placement.leggedOutMessage =
                    "Legged out — leg \(idx + 1) of \(legs.count) failed (\(readable(error))). "
                    + "You now hold an unbalanced position; review your fills before placing more."
                return  // STOP on any failure.
            }
        }
    }

    private func readable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Formatting

    private func money(_ cents: Decimal, negative: Bool = false) -> String {
        let d = NSDecimalNumber(decimal: cents).doubleValue / 100
        return String(format: negative ? "−$%.2f" : "$%.2f", abs(d))
    }
}
