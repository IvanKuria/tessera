import SwiftUI

/// Uppercase category eyebrow (e.g. "POLITICS") used atop cards.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.ui(11, .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// The probability pill — a full-pill outline showing "%". Kalshi's signature
/// at-a-glance chance readout.
struct ProbPill: View {
    let percent: Int?
    var body: some View {
        Text(percent.map { "\($0)%" } ?? "—")
            .font(Theme.num(15, .medium))
            .foregroundStyle(Theme.text)
            .frame(minWidth: 64)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.clear))
            .overlay(Capsule().stroke(Theme.yes, lineWidth: 1))
    }
}

/// A quick-buy YES or NO pill button showing the price in cents.
struct QuickBuyButton: View {
    enum Side { case yes, no }
    let side: Side
    let cents: Int?
    var action: () -> Void = {}

    private var tint: Color { side == .yes ? Theme.yes : Theme.no }
    private var label: String { side == .yes ? "Yes" : "No" }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(Theme.ui(13, .semibold))
                Text(cents.map { "\($0)¢" } ?? "—").font(Theme.num(13, .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(0.06)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Slim probability meter (used in compact rows).
struct ProbabilityBar: View {
    let percent: Int
    var height: CGFloat = 6
    var tint: Color = Theme.yes
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtle)
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * CGFloat(min(100, max(0, percent))) / 100))
            }
        }
        .frame(height: height)
    }
}

/// A category nav tab; selection shown by weight + opacity (Kalshi style).
struct CategoryTab: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.ui(13.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.textTertiary)
                Capsule()
                    .fill(selected ? Theme.text : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Pulsing green LIVE indicator.
struct LiveDot: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(Theme.yes.opacity(0.30))
                    .frame(width: 11, height: 11)
                    .scaleEffect(pulse ? 1.7 : 0.7).opacity(pulse ? 0 : 0.9)
                Circle().fill(Theme.yes).frame(width: 6, height: 6)
            }
            Text("LIVE").font(Theme.ui(10, .bold)).tracking(1.2).foregroundStyle(Theme.yes)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

/// The Tessera wordmark.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.yes)
            Text("Tessera")
                .font(Theme.condensed(20, .semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

/// A simple wrapping (flow) layout — items flow left→right and wrap to the next
/// line when they run out of width. Used for the chart legend so many outcomes
/// don't crowd onto one row.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.width, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A live, pulsing dot — a solid core with a halo that expands and fades,
/// marking the leading (latest) edge of a chart line.
struct PulsingDot: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 16, height: 16)
                .scaleEffect(animate ? 2.4 : 0.7)
                .opacity(animate ? 0 : 0.7)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

/// A small labeled stat (used in detail headers): value over caption.
struct StatBlock: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.num(14, .semibold)).foregroundStyle(valueColor)
            Text(label.uppercased()).font(Theme.ui(9.5, .semibold)).tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
