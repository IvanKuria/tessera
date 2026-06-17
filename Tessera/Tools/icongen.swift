import AppKit
import CoreGraphics
import Foundation

// Tessera app icon generator. A monogram "T" built from mosaic tiles (tesserae),
// glowing mint on a deep green-black field, with one detached "live" tile.
// Run: swift icongen.swift <outputDir>

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

// Mint gradient across the T (brighter at the top of the letter).
func tileColor(_ t: CGFloat) -> CGColor {
    rgb(lerp(0.42, 0.09, t), lerp(0.97, 0.78, t), lerp(0.80, 0.58, t))
}
let bgTop = rgb(0.05, 0.20, 0.15)   // deep teal-green
let bgBot = rgb(0.02, 0.07, 0.05)   // near-black green
let mintBright = rgb(0.55, 0.99, 0.84)

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

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: rgb(0, 0, 0, 0.30))
    ctx.addPath(squircle); ctx.setFillColor(bgBot); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient + faint mosaic grid + top sheen.
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [bgBot, bgTop] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    ctx.setStrokeColor(rgb(1, 1, 1, 0.045)); ctx.setLineWidth(max(1, size * 0.004))
    let cells = 6, step = rect.width / CGFloat(cells)
    for i in 1..<cells {
        let x = rect.minX + CGFloat(i) * step
        ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
        let y = rect.minY + CGFloat(i) * step
        ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    ctx.strokePath()
    let sheen = CGGradient(colorsSpace: cs, colors: [rgb(1,1,1,0.10), rgb(1,1,1,0)] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    // Mosaic "T": crossbar of 3 tiles + a 3-tile stem.
    let tile = rect.width * 0.205
    let gap = tile * 0.20
    let totalW = 3 * tile + 2 * gap
    let totalH = 4 * tile + 3 * gap
    let originX = rect.minX + (rect.width - totalW) / 2
    let originYTop = rect.minY + (rect.height - totalH) / 2 - rect.height * 0.01

    // (col,row) in top-left logical coords; row 0 is the top of the letter.
    func frame(_ col: CGFloat, _ row: CGFloat, inset: CGFloat = 0) -> CGRect {
        let x = originX + col * (tile + gap) + inset
        let yTop = originYTop + row * (tile + gap) + inset
        return CGRect(x: x, y: size - yTop - (tile - 2 * inset), width: tile - 2 * inset, height: tile - 2 * inset)
    }
    func drawTile(_ r: CGRect, _ fill: CGColor, glow: Bool = true) {
        ctx.saveGState()
        if glow { ctx.setShadow(offset: .zero, blur: size * 0.035, color: rgb(0.16, 0.91, 0.66, 0.55)) }
        let rad = r.width * 0.26
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
        ctx.setFillColor(fill); ctx.fillPath()
        ctx.restoreGState()
    }

    // Crossbar (skip top-right — drawn detached) + stem, tinted top→bottom.
    let solid: [(CGFloat, CGFloat, CGFloat)] = [(0,0,0.0), (1,0,0.0), (1,1,0.33), (1,2,0.66), (1,3,1.0)]
    for (c, r, t) in solid { drawTile(frame(c, r), tileColor(t)) }

    // The "live" tessera: top-right crossbar tile, brighter with a ring and a
    // subtle nudge (keeps the T intact while marking the leading tile).
    let live = frame(2, 0).offsetBy(dx: gap * 0.14, dy: gap * 0.30)
    drawTile(live, mintBright)
    let rad = live.width * 0.26
    ctx.addPath(CGPath(roundedRect: live, cornerWidth: rad, cornerHeight: rad, transform: nil))
    ctx.setStrokeColor(rgb(1, 1, 1, 0.9)); ctx.setLineWidth(size * 0.011); ctx.strokePath()

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
