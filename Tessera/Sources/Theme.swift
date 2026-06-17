import SwiftUI

/// Tessera's visual language: a refined dark "trading terminal" — near-black
/// layered surfaces, a signature mint accent, coral for the opposing side, and
/// monospaced numerics for prices. Centralized so every surface stays cohesive.
enum Theme {
    // Surfaces — near-black, slightly cool, layered for depth.
    static let bg          = Color(red: 0.043, green: 0.051, blue: 0.063) // #0B0D10
    static let bgElevated  = Color(red: 0.067, green: 0.078, blue: 0.094) // #111419
    static let card        = Color(red: 0.102, green: 0.118, blue: 0.137) // #1A1E23
    static let cardHover   = Color(red: 0.137, green: 0.157, blue: 0.182) // #232A30
    static let stroke      = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.16)

    // Text ramp.
    static let text          = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let textSecondary = Color(red: 0.57, green: 0.61, blue: 0.66)
    static let textTertiary  = Color(red: 0.36, green: 0.40, blue: 0.45)

    // Accents — Tessera mint (yes) and coral (no).
    static let mint  = Color(red: 0.16, green: 0.91, blue: 0.66) // #29E8A8
    static let coral = Color(red: 1.00, green: 0.40, blue: 0.52) // #FF667F
    static let amber = Color(red: 1.00, green: 0.74, blue: 0.30)

    // Typography — rounded display for headings, monospaced for all numerics.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Mint→teal gradient used for probability fills and the wordmark mark.
    static var mintGradient: LinearGradient {
        LinearGradient(
            colors: [mint.opacity(0.65), mint],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

/// Formats a contract count as a compact volume string (e.g. 12_300 → "12.3k").
func compactVolume(_ n: Int) -> String {
    switch n {
    case 1_000_000...:
        return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...:
        return String(format: "%.1fk", Double(n) / 1_000)
    default:
        return "\(n)"
    }
}
