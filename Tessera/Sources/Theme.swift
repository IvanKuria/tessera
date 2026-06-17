import SwiftUI

/// Tessera's visual language — a faithful port of Kalshi's web app design system.
/// Verified from kalshi.com's live CSS (June 2026): a flat, LIGHT, exchange-grade
/// look with green YES (#0AC285) / red NO (#D91616), prices in cents, hairline
/// borders, no shadows, and full-pill (radius 100) controls.
enum Theme {
    // Semantic market colors.
    static let yes   = Color(hex: 0x0AC285) // YES / up / positive / primary action
    static let no    = Color(hex: 0xD91616) // NO / down / negative
    static let brand = Color(hex: 0x28CC95) // brand/marketing green
    static let forest = Color(hex: 0x003221) // deep brand accent

    // Surfaces — light, flat.
    static let bg      = Color.white
    static let surface = Color.white                 // cards: white + hairline border
    static let subtle  = Color(hex: 0xF7F7F7)        // chip tracks, hover fills
    static let hover   = Color(hex: 0xF0F0F0)
    static let border  = Color.black.opacity(0.07)   // hairline card border
    static let divider = Color.black.opacity(0.10)

    // Text ramp (translucent black, like Kalshi).
    static let text          = Color.black.opacity(0.90)
    static let textSecondary = Color.black.opacity(0.55)
    static let textTertiary  = Color.black.opacity(0.30)
    static let onAccent      = Color.white

    // Up/down price change.
    static let up   = yes
    static let down = no

    // Typography. Kalshi uses proprietary "kalshiSans" (a geometric grotesque) and
    // "kalshiCondensed" for big titles; we substitute the system face + condensed
    // width, with tabular figures for all prices.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Condensed display face for large event/market titles.
    static func condensed(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
    /// Tabular numeric font for prices/percentages (apply to aligned columns).
    static func num(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    // Full-pill corner radius used across controls.
    static let pill: CGFloat = 100
    static let cardRadius: CGFloat = 16
}

extension Color {
    /// Hex literal initializer, e.g. `Color(hex: 0x0AC285)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Formats a contract count as a compact volume string (e.g. 12_300 → "12.3k").
func compactVolume(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...:     return String(format: "%.1fk", Double(n) / 1_000)
    default:           return "\(n)"
    }
}

/// Formats dollars (cents count) as a "$251,590 vol"-style string.
func dollarVolume(_ contracts: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return "$" + (f.string(from: NSNumber(value: contracts)) ?? "\(contracts)")
}
