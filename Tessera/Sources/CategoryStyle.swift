import SwiftUI

/// Maps a Kalshi category to an SF Symbol + color, so cards and detail headers
/// get lively, recognizable thumbnails (the public API exposes no image URLs).
struct CategoryStyle {
    let symbol: String
    let color: Color

    static func of(_ category: String) -> CategoryStyle {
        let c = category.lowercased()
        switch true {
        case c.contains("election"):            return .init(symbol: "checkmark.seal.fill", color: Color(hex: 0x265CFF))
        case c.contains("politic"):             return .init(symbol: "building.columns.fill", color: Color(hex: 0x5B6CFF))
        case c.contains("sport"):               return .init(symbol: "sportscourt.fill", color: Color(hex: 0xFF6A00))
        case c.contains("crypto"):              return .init(symbol: "bitcoinsign.circle.fill", color: Color(hex: 0xF7931A))
        case c.contains("financ"):              return .init(symbol: "chart.xyaxis.line", color: Color(hex: 0x12B886))
        case c.contains("econ"):                return .init(symbol: "chart.line.uptrend.xyaxis", color: Color(hex: 0x0AC285))
        case c.contains("climate"), c.contains("weather"): return .init(symbol: "cloud.sun.fill", color: Color(hex: 0x00B5D9))
        case c.contains("compan"):              return .init(symbol: "building.2.fill", color: Color(hex: 0x7048E8))
        case c.contains("tech"), c.contains("science"): return .init(symbol: "cpu.fill", color: Color(hex: 0x4263EB))
        case c.contains("culture"), c.contains("entertain"): return .init(symbol: "star.fill", color: Color(hex: 0xE64980))
        case c.contains("health"):              return .init(symbol: "cross.case.fill", color: Color(hex: 0xE03131))
        case c.contains("mention"):             return .init(symbol: "quote.bubble.fill", color: Color(hex: 0x868E96))
        case c.contains("world"):               return .init(symbol: "globe.americas.fill", color: Color(hex: 0x1098AD))
        case c.contains("commodit"):            return .init(symbol: "drop.fill", color: Color(hex: 0xF59F00))
        case c.contains("media"):               return .init(symbol: "play.rectangle.fill", color: Color(hex: 0xE8590C))
        default:                                return .init(symbol: "chart.bar.fill", color: Color(hex: 0x868E96))
        }
    }
}

/// A rounded, gradient-filled category tile with a white glyph.
struct CategoryIcon: View {
    let category: String
    var size: CGFloat = 28

    var body: some View {
        let style = CategoryStyle.of(category)
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(style.color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}
