import SwiftUI
import AppKit

/// Tessera's visual language — a port of Kalshi's exchange-grade design system,
/// with green YES (#0AC285) / red NO (#D91616), prices in cents, hairline borders,
/// and full-pill (radius 100) controls.
///
/// Surfaces and the text ramp are **appearance-adaptive**: each is a
/// `Color(light:dark:)` pair that resolves per render, so the whole app — and any
/// new view that uses these tokens — follows light/dark automatically. Use these
/// tokens for surfaces/text/borders instead of raw `Color.white`/`.black`.
enum Theme {
    // Semantic market colors (vivid; read well on both light and dark).
    static let yes   = Color(hex: 0x0AC285) // YES / up / positive / primary action
    static let no    = Color(hex: 0xD91616) // NO / down / negative
    static let brand = Color(hex: 0x28CC95) // brand/marketing green
    static let forest = Color(hex: 0x003221) // deep brand accent
    static let info  = Color(hex: 0x265CFF) // neutral accent: in-progress / informational (overlays, MA line)

    // Surfaces — light: flat white; dark: charcoal with lifted cards.
    static let bg      = Color(light: .white,               dark: Color(hex: 0x181A1E))
    static let surface = Color(light: .white,               dark: Color(hex: 0x202328)) // cards
    static let subtle  = Color(light: Color(hex: 0xF7F7F7), dark: Color(hex: 0x26292F)) // chip tracks, hover fills
    static let hover   = Color(light: Color(hex: 0xF0F0F0), dark: Color(hex: 0x2D3037))
    static let border  = Color(light: .black.opacity(0.07), dark: .white.opacity(0.10)) // hairline card border
    static let divider = Color(light: .black.opacity(0.10), dark: .white.opacity(0.14))

    // Text ramp (translucent black on light, translucent white on dark).
    static let text          = Color(light: .black.opacity(0.90), dark: .white.opacity(0.92))
    static let textSecondary = Color(light: .black.opacity(0.55), dark: .white.opacity(0.60))
    static let textTertiary  = Color(light: .black.opacity(0.30), dark: .white.opacity(0.38))
    static let onAccent      = Color.white // text/icons on the green/red accent fills

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
    /// An appearance-adaptive color: resolves to `light` in light mode and `dark`
    /// in dark mode, re-evaluating whenever the effective appearance changes
    /// (system switch or in-app override).
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }

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
