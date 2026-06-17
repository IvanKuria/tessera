import SwiftUI

/// A market event rendered as a card. Binary events get a prominent YES/NO price
/// row + probability meter; multi-outcome events list their outcomes with bars.
struct EventCardView: View {
    let event: EventVM
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if event.isBinary, let outcome = event.topOutcome {
                binaryBody(outcome)
            } else {
                multiBody
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hover ? Theme.cardHover : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(hover ? Theme.strokeStrong : Theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(hover ? 0.35 : 0.18), radius: hover ? 14 : 7, y: 5)
        .scaleEffect(hover ? 1.006 : 1)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                CategoryTag(text: event.category)
                Text(event.title)
                    .font(Theme.display(15.5, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if event.isBinary, let p = event.topOutcome?.percent {
                Text("\(p)")
                    .font(Theme.mono(30, .bold))
                    .foregroundStyle(Theme.mint)
                    .overlay(alignment: .topTrailing) {
                        Text("%").font(Theme.mono(12, .bold)).foregroundStyle(Theme.mint.opacity(0.7))
                            .offset(x: 13, y: 2)
                    }
            }
        }
    }

    private func binaryBody(_ outcome: OutcomeVM) -> some View {
        VStack(spacing: 12) {
            ProbabilityBar(percent: outcome.percent ?? 0, height: 7)
            HStack(spacing: 8) {
                PricePill(label: "YES", cents: outcome.yesCents, tint: Theme.mint)
                PricePill(label: "NO", cents: outcome.noCents, tint: Theme.coral)
                Spacer()
                volumeLabel
            }
        }
    }

    private var multiBody: some View {
        VStack(spacing: 10) {
            ForEach(event.outcomes.prefix(4)) { outcome in
                HStack(spacing: 12) {
                    Text(outcome.label)
                        .font(Theme.body(12.5, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    ProbabilityBar(percent: outcome.percent ?? 0)
                    Text(outcome.percent.map { "\($0)%" } ?? "—")
                        .font(Theme.mono(12.5, .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 46, alignment: .trailing)
                }
            }
            if event.outcomes.count > 4 {
                HStack {
                    Text("+\(event.outcomes.count - 4) more outcomes")
                        .font(Theme.body(11)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    volumeLabel
                }
            } else {
                HStack { Spacer(); volumeLabel }
            }
        }
    }

    private var volumeLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill").font(.system(size: 8))
            Text("Vol \(compactVolume(event.totalVolume))").font(Theme.mono(10.5, .medium))
        }
        .foregroundStyle(Theme.textTertiary)
    }
}
