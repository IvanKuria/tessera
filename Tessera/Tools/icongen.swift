import AppKit
import CoreGraphics
import Foundation

// Tessera app icon generator. Renders the mark at native pixel sizes (crisp at
// every scale) and writes PNGs into an AppIcon.appiconset.
//
// Concept: a mint→forest squircle (Kalshi palette, original composition) with
// three ascending white tiles (rising odds) and a detached "tessera" tile above
// the leader, over a faint mosaic grid. Run: swift icongen.swift <outputDir>

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}

let mint   = color(0.16, 0.91, 0.66)   // #29E8A8
let midGrn = color(0.04, 0.55, 0.42)
let forest = color(0.00, 0.18, 0.12)   // #002E1F

func makeIcon(_ size: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: rounded rect inset with padding, ~22.5% corner radius.
    let pad = size * 0.094
    let rect = CGRect(x: pad, y: pad, width: size - 2 * pad, height: size - 2 * pad)
    let corner = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Soft drop shadow beneath the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.03, color: color(0, 0, 0, 0.28))
    ctx.addPath(squircle); ctx.setFillColor(forest); ctx.fillPath()
    ctx.restoreGState()

    // Gradient fill (CG is bottom-up: bottom=forest, top=mint).
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [forest, midGrn, mint] as CFArray,
                          locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.minY),
                           end: CGPoint(x: rect.midX, y: rect.maxY), options: [])

    // Faint mosaic grid (the "tessera" identity).
    ctx.setStrokeColor(color(1, 1, 1, 0.05))
    ctx.setLineWidth(max(1, size * 0.004))
    let cells = 6
    let step = rect.width / CGFloat(cells)
    for i in 1..<cells {
        let x = rect.minX + CGFloat(i) * step
        ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
        let y = rect.minY + CGFloat(i) * step
        ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    ctx.strokePath()

    // Top sheen.
    let sheen = CGGradient(colorsSpace: cs, colors: [color(1,1,1,0.14), color(1,1,1,0)] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    // Ascending tiles. Content area inset within the squircle.
    let ax = rect.minX + rect.width * 0.24
    let ay = rect.minY + rect.height * 0.26
    let aw = rect.width * 0.52
    let ah = rect.height * 0.46
    let area = CGRect(x: ax, y: ay, width: aw, height: ah)

    let n = 3
    let gap = area.width * 0.13
    let barW = (area.width - gap * CGFloat(n - 1)) / CGFloat(n)
    let heights: [CGFloat] = [0.46, 0.70, 1.0]
    func tile(_ r: CGRect, _ fill: CGColor, radiusFrac: CGFloat = 0.30) {
        let rad = min(r.width, r.height) * radiusFrac
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
        ctx.setFillColor(fill); ctx.fillPath()
    }
    for i in 0..<n {
        let h = area.height * heights[i]
        let x = area.minX + CGFloat(i) * (barW + gap)
        tile(CGRect(x: x, y: area.minY, width: barW, height: h),
             color(1, 1, 1, i == n - 1 ? 1.0 : 0.82))
    }

    // Detached "tessera" tile above the leader (the latest data point).
    let t = barW * 0.92
    let tx = area.minX + 2 * (barW + gap) + (barW - t) / 2
    let ty = area.minY + area.height * 1.0 + gap * 0.55
    tile(CGRect(x: tx, y: ty, width: t, height: t), mint, radiusFrac: 0.28)
    // thin white ring so the mint tile reads on the mint upper gradient
    let ring = barW * 0.92
    let rrad = ring * 0.28
    ctx.addPath(CGPath(roundedRect: CGRect(x: tx, y: ty, width: ring, height: ring),
                       cornerWidth: rrad, cornerHeight: rrad, transform: nil))
    ctx.setStrokeColor(color(1, 1, 1, 0.85)); ctx.setLineWidth(size * 0.012); ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let img = makeIcon(CGFloat(px))
    writePNG(img, to: outDir.appendingPathComponent("icon_\(px).png"))
    print("wrote icon_\(px).png")
}
