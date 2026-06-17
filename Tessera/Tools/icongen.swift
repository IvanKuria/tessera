import AppKit
import CoreGraphics
import Foundation

// Tessera app icon — an abstract radial "bloom": tapered rays fanning from a
// center hub, monochrome cream on a brand mint→teal squircle (colored field +
// single-color abstract mark). Run: swift icongen.swift <outputDir>

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}

let bgTop = rgb(0.16, 0.86, 0.64)   // mint
let bgBot = rgb(0.02, 0.30, 0.23)   // deep teal
let mark  = rgb(0.96, 1.00, 0.98)   // soft cream-white

func makeIcon(_ size: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let pad = size * 0.094
    let rect = CGRect(x: pad, y: pad, width: size - 2 * pad, height: size - 2 * pad)
    let corner = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Drop shadow + gradient field.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: rgb(0, 0, 0, 0.30))
    ctx.addPath(squircle); ctx.setFillColor(bgBot); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [bgBot, bgTop] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    // soft radial vignette for depth
    let vig = CGGradient(colorsSpace: cs, colors: [rgb(1,1,1,0.10), rgb(1,1,1,0)] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(vig, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                           endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.5, options: [])
    ctx.restoreGState()

    // Abstract radial burst: rounded spokes of varying length fanning out, with
    // a soft organic rhythm (not a star, not a flower).
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let count = 15
    let inner = rect.width * 0.05            // spokes start just off-center
    let baseLen = rect.width * 0.40          // outer reach
    let rayW = rect.width * 0.040

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.006), blur: size * 0.022, color: rgb(0, 0.18, 0.13, 0.30))
    ctx.setStrokeColor(mark)
    ctx.setLineCap(.round)
    ctx.setLineWidth(rayW)

    for i in 0..<count {
        let theta = (CGFloat(i) / CGFloat(count)) * 2 * .pi - .pi / 2
        // Two-lobe smooth variation + a small alternating step → organic rhythm.
        let wave = 0.5 + 0.5 * sin(theta * 2 + 0.6)
        let step: CGFloat = (i % 2 == 0) ? 1.0 : 0.84
        let lenFrac = (0.60 + 0.40 * wave) * step
        let outer = inner + (baseLen - inner) * lenFrac
        let dir = CGPoint(x: cos(theta), y: sin(theta))
        ctx.move(to: CGPoint(x: center.x + dir.x * inner, y: center.y + dir.y * inner))
        ctx.addLine(to: CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Soft center hub where the spokes converge.
    ctx.setFillColor(mark)
    let hub = rect.width * 0.105
    ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
    // a small deep-teal core for depth + a touch of brand.
    ctx.setFillColor(bgBot)
    let core = hub * 0.42
    ctx.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(makeIcon(CGFloat(px)), to: outDir.appendingPathComponent("icon_\(px).png"))
    print("wrote icon_\(px).png")
}
