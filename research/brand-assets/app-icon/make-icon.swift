#!/usr/bin/env swift
// make-icon.swift — the Cockatoo app-icon background, reusable.
//
// Renders the "button-looking" macOS icon tile: Apple's Big Sur icon-grid
// squircle (tile = 824/1024 of the canvas, the OS supplies the drop
// shadow), filled with a graphite top-to-bottom gradient and edged with a
// faint gold rim. Optionally composites a glyph PNG on top, then emits
// every size an AppIcon.appiconset needs.
//
// Usage:
//   swift make-icon.swift <outdir>                        # background only
//   swift make-icon.swift <outdir> <glyph.png> [scale]    # + centered glyph
//
// scale = glyph width as a fraction of the tile (default 0.62).
// Recipe knobs are the constants below — retint them for another app.

import AppKit

// ── The recipe ────────────────────────────────────────────────────────
let canvas: CGFloat = 1024
let tile: CGFloat = 824              // Apple icon-grid tile (824/1024)
let cornerRadius: CGFloat = 180      // ≈ 0.218 × tile
let fillTop = NSColor(srgbRed: 0x25/255.0, green: 0x25/255.0, blue: 0x27/255.0, alpha: 1)   // #252527
let fillBottom = NSColor(srgbRed: 0x13/255.0, green: 0x13/255.0, blue: 0x14/255.0, alpha: 1) // #131314
let rimColor = NSColor(srgbRed: 0xF2/255.0, green: 0xC5/255.0, blue: 0x3A/255.0, alpha: 0.18) // gold @ 18%
let rimWidth: CGFloat = 6            // at 1024; scales with size
// ──────────────────────────────────────────────────────────────────────

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: swift make-icon.swift <outdir> [glyph.png] [glyphScale]")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let glyph: NSImage? = args.count >= 3 ? NSImage(contentsOfFile: args[2]) : nil
let glyphScale: CGFloat = args.count >= 4 ? CGFloat(Double(args[3]) ?? 0.62) : 0.62

func render(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size) / canvas
    // sRGB end-to-end, or the hex values above gamma-shift on the way in.
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let inset = (canvas - tile) / 2 * s
    let rect = NSRect(x: inset, y: inset, width: tile * s, height: tile * s)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius * s, yRadius: cornerRadius * s)

    // Graphite gradient, light at the top.
    NSGradient(starting: fillTop, ending: fillBottom)!.draw(in: squircle, angle: -90)

    // Faint gold rim, stroked just inside the edge so nothing clips.
    let rimInset = rimWidth * s / 2
    let rimRect = rect.insetBy(dx: rimInset, dy: rimInset)
    let rim = NSBezierPath(roundedRect: rimRect, xRadius: (cornerRadius * s) - rimInset, yRadius: (cornerRadius * s) - rimInset)
    rimColor.setStroke()
    rim.lineWidth = rimWidth * s
    rim.stroke()

    if let glyph {
        let gw = tile * s * glyphScale
        let gh = gw * (glyph.size.height / glyph.size.width)
        let gRect = NSRect(x: (CGFloat(size) - gw) / 2, y: (CGFloat(size) - gh) / 2, width: gw, height: gh)
        glyph.draw(in: gRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
    print("  \(name)")
}

// The ten macOS appiconset entries + a loose 1024 preview.
for (point, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let px = point * scale
        write(render(size: px), scale == 1 ? "icon_\(point).png" : "icon_\(point)@2x.png")
    }
}
write(render(size: 1024), "icon-1024.png")
print("done → \(outDir.path)")
