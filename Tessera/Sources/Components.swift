import SwiftUI

/// Slim probability meter: a track with a mint gradient fill proportional to %.
struct ProbabilityBar: View {
    let percent: Int
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Theme.mintGradient)
                    .frame(width: max(0, geo.size.width * CGFloat(min(100, max(0, percent))) / 100))
            }
        }
        .frame(height: height)
    }
}

/// A YES/NO buy-price pill in the side's accent color.
struct PricePill: View {
    let label: String
    let cents: Int?
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.mono(10, .bold)).tracking(0.8)
            Text(cents.map { "\($0)¢" } ?? "—").font(Theme.mono(13, .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
    }
}

/// A small uppercase category tag.
struct CategoryTag: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(9.5, .bold)).tracking(1.2)
            .foregroundStyle(Theme.mint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.mint.opacity(0.10)))
    }
}

/// A pulsing "LIVE" indicator.
struct LiveDot: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(Theme.mint.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.6 : 0.8)
                    .opacity(pulse ? 0 : 0.8)
                Circle().fill(Theme.mint).frame(width: 6, height: 6)
            }
            Text("LIVE").font(Theme.mono(9.5, .bold)).tracking(1.4).foregroundStyle(Theme.mint)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Selectable category filter chip.
struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.bg : Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Color.white.opacity(0.05)))
                )
                .overlay(Capsule().stroke(selected ? Color.clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The Tessera wordmark: a mint mosaic mark + the name in a rounded display face.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            // Four mosaic tiles — the "tessera".
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.mintGradient)
            Text("TESSERA")
                .font(Theme.display(17, .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.text)
        }
    }
}
