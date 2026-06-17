import SwiftUI

/// A circular outcome avatar: a real portrait (resolved from Wikipedia) when one
/// exists, otherwise initials on a tinted disc. The ring is tinted to match the
/// outcome's chart-line color, tying the list row to the chart.
struct OutcomeAvatar: View {
    let name: String
    var ring: Color = Theme.textTertiary
    var size: CGFloat = 32

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
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring.opacity(0.65), lineWidth: 1.5))
        .task(id: name) {
            url = await PortraitService.shared.thumbnail(for: name)
        }
    }

    private var initials: some View {
        Text(initialsText)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(ring.opacity(0.9))
    }

    private var initialsText: String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        return String(chars).uppercased()
    }
}
