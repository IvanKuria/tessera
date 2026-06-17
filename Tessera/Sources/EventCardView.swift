import SwiftUI
import KalshiKit

/// A Kalshi-style event card: white, flat, hairline border, no shadow.
/// Binary events show a YES/NO quick-buy row; multi-outcome events list their
/// top outcomes with probability pills.
struct EventCardView: View {
    let event: EventVM
    var onOpen: () -> Void
    var onBuy: (_ marketTicker: String, _ side: OrderSide) -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Eyebrow(text: event.category)
                        Spacer()
                        if event.isBinary, let p = event.topOutcome?.percent {
                            ProbPill(percent: p)
                        }
                    }
                    Text(event.title)
                        .font(Theme.ui(15.5, .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !event.isBinary { outcomePreview }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if event.isBinary, let outcome = event.topOutcome {
                HStack(spacing: 8) {
                    QuickBuyButton(side: .yes, cents: outcome.yesCents) { onBuy(outcome.id, .yes) }
                    QuickBuyButton(side: .no, cents: outcome.noCents) { onBuy(outcome.id, .no) }
                }
            }

            footer
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

    private var outcomePreview: some View {
        VStack(spacing: 9) {
            ForEach(event.outcomes.prefix(2)) { outcome in
                HStack(spacing: 10) {
                    Text(outcome.label)
                        .font(Theme.ui(13.5)).foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let p = outcome.percent, p > 0 {
                        Text(String(format: "%.1fx", 100.0 / Double(p)))
                            .font(Theme.num(11)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    ProbPill(percent: outcome.percent)
                }
            }
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack {
            Label("Vol \(compactVolume(event.totalVolume))", systemImage: "chart.bar.fill")
                .font(Theme.num(11)).foregroundStyle(Theme.textTertiary)
                .labelStyle(.titleAndIcon)
            Spacer()
            if !event.isBinary {
                Text("\(event.outcomes.count) outcomes")
                    .font(Theme.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
            } else if let close = event.closeTime {
                Text("Closes \(close.formatted(.dateTime.month().day()))")
                    .font(Theme.ui(11)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
