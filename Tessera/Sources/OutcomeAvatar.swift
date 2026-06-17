import SwiftUI

/// A circular outcome avatar: a real portrait (resolved from Wikipedia) when one
/// exists, otherwise initials on a tinted disc. The ring is tinted to match the
/// outcome's chart-line color, tying the list row to the chart.
struct OutcomeAvatar: View {
    let name: String
    var ring: Color = Theme.textTertiary
    var size: CGFloat = 32
    /// Only attempt a Wikipedia portrait when the event's outcomes are people/orgs.
    /// For sports teams, commodities, thresholds, etc. we show clean initials.
    var peopleLikely: Bool = true

    @State private var url: URL?

    var body: some View {
        ZStack {
            Circle().fill(ring.opacity(0.14))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring.opacity(0.65), lineWidth: 1.5))
        .task(id: name) {
            url = peopleLikely ? await PortraitService.shared.thumbnail(for: name) : nil
        }
    }

    /// Initials when we have them, else a neutral glyph — never blank.
    @ViewBuilder private var placeholder: some View {
        let text = initialsText
        if text.isEmpty {
            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(ring.opacity(0.8))
        } else {
            Text(text)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(ring.opacity(0.95))
        }
    }

    private var initialsText: String {
        let parts = name
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .prefix(2)
        let chars = parts.compactMap { $0.first(where: \.isLetter) ?? $0.first(where: \.isNumber) }
        return String(chars).uppercased()
    }
}
