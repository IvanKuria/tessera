import SwiftUI

/// A market's thumbnail. For a people-style race it shows the **currently
/// leading** outcome's portrait (resolved from Wikipedia); otherwise it falls
/// back to the category icon. Rounded-square, like Kalshi's event tiles.
struct EventIcon: View {
    let event: EventVM
    var size: CGFloat = 28

    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        CategoryIcon(category: event.category, size: size)
                    }
                }
            } else {
                CategoryIcon(category: event.category, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .task(id: leaderName) {
            guard let leaderName else { url = nil; return }
            url = await PortraitService.shared.thumbnail(for: leaderName)
        }
    }

    /// The leading outcome's name — only for categories whose outcomes are people
    /// / orgs (so we don't mis-resolve sports lines or numeric thresholds).
    private var leaderName: String? {
        guard !event.isBinary, let leader = event.topOutcome,
              CategoryStyle.hasPeopleOutcomes(event.category) else { return nil }
        return leader.label
    }
}
