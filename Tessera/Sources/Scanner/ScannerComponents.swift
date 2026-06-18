import SwiftUI
import KalshiKit

/// Warning amber — the single non-green/red accent allowed in the Scanner, and
/// only for warning chips and the mid-freshness state (the app otherwise avoids
/// orange). Matches the candlestick MA convention exception.
private let warningAmber = Color(hex: 0xF59F00)

// MARK: - Lane tag

/// A tiny pill labeling which lane an opportunity belongs to. Color is never the
/// only signal — the glyph + word "LOCK"/"EDGE" carry the meaning too.
struct LaneTag: View {
    let lane: OpportunityLane
    var body: some View {
        let lock = lane == .lock
        HStack(spacing: 4) {
            Image(systemName: lock ? "lock.fill" : "diamond.fill")
                .font(.system(size: 8, weight: .bold))
            Text(lock ? "LOCK" : "EDGE")
                .font(Theme.ui(9, .bold)).tracking(0.6)
        }
        .foregroundStyle(lock ? Theme.yes : Theme.info)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(Capsule().fill((lock ? Theme.yes : Theme.info).opacity(0.12)))
    }
}

// MARK: - Freshness stamp

/// Auto-aging freshness readout: `NEW · 4s` → `updated 8s · 🟢` → `updated 34s · 🟡`
/// → `stale · ⚠`. The word always accompanies the dot (color is never alone).
struct FreshnessStamp: View {
    let age: Double           // seconds
    var isNew: Bool = false

    private var dotColor: Color {
        age <= 15 ? Theme.yes : age <= 60 ? warningAmber : Theme.no
    }
    private var label: String {
        if isNew && age <= 10 { return "NEW · \(Int(age))s" }
        if age <= 60 { return "updated \(Int(age))s ago" }
        return "stale · \(Int(age))s"
    }
    private var textColor: Color {
        age <= 15 ? Theme.textSecondary : age <= 60 ? warningAmber : Theme.no
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(label).font(Theme.num(10)).foregroundStyle(textColor)
        }
    }
}

// MARK: - Net-edge hero

/// The headline net-of-fee edge. Green + "net" for Locks (provable); neutral info
/// blue + "~"/"est." for Edges (scored, not guaranteed).
struct NetEdgeHero: View {
    let cents: Double
    let lane: OpportunityLane
    var body: some View {
        let est = lane == .edge
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(est ? "~" : "+")\(cents, specifier: "%.1f")¢")
                .font(Theme.num(28, .semibold))
                .foregroundStyle(lane == .lock ? Theme.yes : Theme.info)
            Text(est ? "est. edge / contract" : "net edge / contract")
                .font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Confidence meter

/// Five-segment confidence readout (Edges are scored, not guaranteed).
struct ConfidenceMeter: View {
    let score: Double   // 0…1
    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(i) < score * 5 ? Theme.info : Theme.subtle)
                        .frame(width: 8, height: 6)
                }
            }
            Text("\(Int(score * 100))").font(Theme.num(10)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Warning chip

/// A short warning chip (thin depth / below hurdle / stale …). Amber by default;
/// neutral for non-alarming, informational warnings like settlement discretion.
struct WarningChip: View {
    let text: String
    var neutral: Bool = false
    var glyph: String = "exclamationmark.triangle.fill"

    private var tint: Color { neutral ? Theme.textSecondary : warningAmber }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: glyph).font(.system(size: 8))
            Text(text).font(Theme.ui(10, .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(neutral ? 0.10 : 0.14)))
    }
}

// MARK: - Venue badge (cross-venue arbitrage)

/// A tiny pill naming which exchange a leg trades on. Kalshi green / Polymarket
/// violet. Only shown for cross-venue opportunities (where `Leg.venue` is set);
/// single-venue Scanner legs leave `venue == nil` and render no badge, so the
/// Scanner UI is unaffected. Color is always paired with the venue's name.
struct VenueBadge: View {
    let venue: Venue
    /// Distinct violet for Polymarket; the brand green for Kalshi.
    static let polymarketViolet = Color(hex: 0x8B5CF6)

    private var tint: Color { venue == .kalshi ? Theme.yes : Self.polymarketViolet }
    private var label: String { venue == .kalshi ? "Kalshi" : "Polymarket" }

    var body: some View {
        Text(label)
            .font(Theme.ui(9, .bold)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 0.5))
    }
}

// MARK: - Lane / mode toggle

/// The pill segmented toggle, identical in style to DetailView's Line/Candles
/// control: subtle track, lifted selected thumb, all Theme colors. Generic over
/// the selection value; each option carries an optional inline count.
struct LaneModeToggle<T: Hashable>: View {
    let options: [(value: T, label: String, count: Int?)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                let selected = selection == opt.value
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = opt.value }
                } label: {
                    HStack(spacing: 5) {
                        Text(opt.label)
                            .font(Theme.ui(12, selected ? .semibold : .regular))
                        if let n = opt.count {
                            Text("\(n)")
                                .font(Theme.num(11, .semibold))
                                .foregroundStyle(selected ? Theme.textSecondary : Theme.textTertiary)
                        }
                    }
                    .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.surface : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
    }
}

// MARK: - Empty / placeholder states

/// Honest empty state — a quiet market is normal, not a failure.
struct ScannerEmptyState: View {
    let lane: OpportunityLane
    var body: some View {
        let lock = lane == .lock
        VStack(spacing: 10) {
            Image(systemName: lock ? "lock.open" : "diamond")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(lock ? "No locks right now — and that's normal." : "No edges right now.")
                .font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text)
            Text(lock
                 ? "Provable arbitrage is rare. When a mutually-exclusive market misprices past fees and depth, it'll appear here. We keep scanning."
                 : "Scored signals — wide spreads, stale quotes, ladder slips — show up here as the market moves. We keep scanning.")
                .font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 60)
    }
}

// MARK: - Opportunity display helpers

extension Opportunity {
    /// Per-contract net edge in cents, as a Double (display only).
    var netEdgePerContractDouble: Double { NSDecimalNumber(decimal: netEdgePerContractCents).doubleValue }
    var annualizedDouble: Double { NSDecimalNumber(decimal: annualizedPct).doubleValue }
    var netEdgeDollarsDouble: Double { NSDecimalNumber(decimal: netEdgeCents).doubleValue / 100 }
    var capitalDollarsDouble: Double { NSDecimalNumber(decimal: capitalRequiredCents).doubleValue / 100 }
    var maxLossDollarsDouble: Double { NSDecimalNumber(decimal: maxLossIfLeggedOutCents).doubleValue / 100 }
    var confidenceDouble: Double { NSDecimalNumber(decimal: confidence).doubleValue }
    var daysToSettlementDouble: Double { NSDecimalNumber(decimal: daysToSettlement).doubleValue }
    var maxContractsInt: Int { NSDecimalNumber(decimal: maxContractsAtPositiveEdge).intValue }

    /// Dollar capital actually deployable = fillable contracts × per-contract cost.
    var fitsDollars: Double {
        guard let q = legs.first?.qty, q > 0 else { return 0 }
        let perContractCapitalCents = capitalRequiredCents / q
        let dollars = (maxContractsAtPositiveEdge * perContractCapitalCents) / 100
        return NSDecimalNumber(decimal: dollars).doubleValue
    }

    /// Flag-only Edges (wide-spread / stale subtypes) carry no real dollar figure —
    /// they're a signal, not a sized trade. Render them without a "fits"/profit number.
    var isFlagOnly: Bool {
        switch kind {
        case .edge(.wideSpread), .edge(.staleQuote): return true
        default: return false
        }
    }

    /// Short human title for the opportunity kind.
    var kindLabel: String {
        switch kind {
        case .lock(.multiOutcomeUnderround): return "Underround lock"
        case .lock(.multiOutcomeOverround):  return "Overround lock"
        case .edge(.ladderMonotonicity):     return "Ladder slip"
        case .edge(.wideSpread):             return "Wide spread"
        case .edge(.staleQuote):             return "Stale quote"
        case .edge(.crossVenueArb):          return "Cross-venue arb"
        }
    }

    /// Maps engine warnings to short chip descriptors. `neutral` warnings use a
    /// quiet tint (not alarming). Returns nil for warnings with no user-facing chip.
    var warningChips: [(text: String, neutral: Bool)] {
        warnings.compactMap { w in
            switch w {
            case .oneContractMirage:   return ("thin depth", false)
            case .thinDepth:           return ("thin depth", false)
            case .belowHurdle:         return ("below hurdle", false)
            case .possibleNonTiling:   return ("check tiling", false)
            case .settlementDiscretion: return ("settles by rule", true)
            case .wideSpread:          return ("wide spread", false)
            case .staleQuote:          return ("stale", false)
            case .feeKilledNearMid:    return ("fee-thin", false)
            case .bookIntegrity:       return nil
            // Cross-venue (arbitrage) warnings.
            case .crossVenueSettlement: return ("cross-venue settlement", false)
            case .resolutionMismatch:   return ("resolution mismatch", false)
            case .lowMatchConfidence:   return ("low match confidence", false)
            }
        }
    }
}
