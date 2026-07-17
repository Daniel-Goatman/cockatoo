#!/usr/bin/env swift
// Deterministically renders Cockatoo's compact-bust mark into every macOS
// AppIcon size. The path coordinates mirror `cockatoo-mark.svg` and
// `App/Cockatoo/Cockatoo/BrandMark.swift`.
//
// Usage: swift make-icon.swift <AppIcon.appiconset directory>

import AppKit

let canvas: CGFloat = 1024
let tile: CGFloat = 824
let cornerRadius: CGFloat = 180
let defaultMarkScale: CGFloat = 0.69
let fillTop = NSColor(srgbRed: 0x25/255.0, green: 0x25/255.0, blue: 0x27/255.0, alpha: 1)
let fillBottom = NSColor(srgbRed: 0x13/255.0, green: 0x13/255.0, blue: 0x14/255.0, alpha: 1)
let bodyColor = NSColor(srgbRed: 0xF2/255.0, green: 0xF0/255.0, blue: 0xE8/255.0, alpha: 1)
let crestColor = NSColor(srgbRed: 0xF5/255.0, green: 0xC5/255.0, blue: 0x2B/255.0, alpha: 1)
let beakColor = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x1A/255.0, alpha: 1)
let rimColor = NSColor(srgbRed: 0xF2/255.0, green: 0xC5/255.0, blue: 0x3A/255.0, alpha: 0.18)
let rimWidth: CGFloat = 6

guard CommandLine.arguments.count == 2 else {
    print("usage: swift make-icon.swift <AppIcon.appiconset directory>")
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func bodyPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 29, y: 92))
    path.addCurve(to: CGPoint(x: 36, y: 45), control1: CGPoint(x: 34, y: 78), control2: CGPoint(x: 36, y: 62))
    path.addCurve(to: CGPoint(x: 55, y: 14), control1: CGPoint(x: 36, y: 29), control2: CGPoint(x: 43, y: 18))
    path.addCurve(to: CGPoint(x: 83, y: 31), control1: CGPoint(x: 69, y: 10), control2: CGPoint(x: 80, y: 18))
    path.addCurve(to: CGPoint(x: 80, y: 48), control1: CGPoint(x: 85, y: 38), control2: CGPoint(x: 84, y: 43))
    path.addCurve(to: CGPoint(x: 73, y: 65), control1: CGPoint(x: 76, y: 53), control2: CGPoint(x: 73, y: 59))
    path.addCurve(to: CGPoint(x: 79, y: 92), control1: CGPoint(x: 72, y: 73), control2: CGPoint(x: 75, y: 84))
    path.addCurve(to: CGPoint(x: 29, y: 92), control1: CGPoint(x: 65, y: 98), control2: CGPoint(x: 43, y: 98))
    path.closeSubpath()
    return path
}

func crestRootPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 38, y: 20))
    path.addCurve(to: CGPoint(x: 54, y: 36), control1: CGPoint(x: 49, y: 20), control2: CGPoint(x: 54, y: 27))
    path.addCurve(to: CGPoint(x: 38, y: 50), control1: CGPoint(x: 54, y: 45), control2: CGPoint(x: 48, y: 50))
    path.addCurve(to: CGPoint(x: 38, y: 20), control1: CGPoint(x: 42, y: 42), control2: CGPoint(x: 43, y: 29))
    path.closeSubpath()
    return path
}

func crestPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 51, y: 22))
    path.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 37, y: 19), control2: CGPoint(x: 22, y: 12))
    path.addCurve(to: CGPoint(x: 38, y: 31), control1: CGPoint(x: 10, y: 12), control2: CGPoint(x: 19, y: 24))
    path.addCurve(to: CGPoint(x: 51, y: 22), control1: CGPoint(x: 44, y: 32), control2: CGPoint(x: 49, y: 28))
    path.closeSubpath()

    path.move(to: CGPoint(x: 47, y: 29))
    path.addCurve(to: CGPoint(x: 6, y: 16), control1: CGPoint(x: 31, y: 29), control2: CGPoint(x: 17, y: 24))
    path.addCurve(to: CGPoint(x: 39, y: 39), control1: CGPoint(x: 8, y: 28), control2: CGPoint(x: 20, y: 37))
    path.addCurve(to: CGPoint(x: 47, y: 29), control1: CGPoint(x: 44, y: 38), control2: CGPoint(x: 47, y: 34))
    path.closeSubpath()

    path.move(to: CGPoint(x: 42, y: 37))
    path.addCurve(to: CGPoint(x: 7, y: 32), control1: CGPoint(x: 28, y: 40), control2: CGPoint(x: 16, y: 38))
    path.addCurve(to: CGPoint(x: 40, y: 46), control1: CGPoint(x: 12, y: 44), control2: CGPoint(x: 25, y: 49))
    path.addCurve(to: CGPoint(x: 42, y: 37), control1: CGPoint(x: 43, y: 43), control2: CGPoint(x: 44, y: 40))
    path.closeSubpath()
    return path
}

func upperBeakPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 78, y: 40))
    path.addCurve(to: CGPoint(x: 93, y: 46), control1: CGPoint(x: 84, y: 36), control2: CGPoint(x: 91, y: 39))
    path.addCurve(to: CGPoint(x: 84, y: 69), control1: CGPoint(x: 95, y: 53), control2: CGPoint(x: 91, y: 61))
    path.addCurve(to: CGPoint(x: 78, y: 58), control1: CGPoint(x: 85, y: 64), control2: CGPoint(x: 82, y: 59))
    path.addCurve(to: CGPoint(x: 72, y: 51), control1: CGPoint(x: 74, y: 59), control2: CGPoint(x: 71, y: 56))
    path.addCurve(to: CGPoint(x: 78, y: 40), control1: CGPoint(x: 72, y: 46), control2: CGPoint(x: 75, y: 42))
    path.closeSubpath()
    return path
}

func drawMark(in context: CGContext, rect: CGRect) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 100, y: -rect.height / 100)

    context.addPath(crestRootPath())
    context.setFillColor(crestColor.cgColor)
    context.fillPath()

    context.addPath(crestPath())
    context.setFillColor(crestColor.cgColor)
    context.fillPath()

    context.addPath(bodyPath())
    context.setFillColor(bodyColor.cgColor)
    context.fillPath()

    context.addPath(upperBeakPath())
    context.setFillColor(beakColor.cgColor)
    context.setStrokeColor(bodyColor.cgColor)
    // Retain a visible pale outer contour in the optical-size variants. At
    // 16px macOS otherwise merges the dark bill into the graphite tile.
    let dividerPixels: CGFloat = rect.width < 20 ? 1.5 : 0.9
    context.setLineWidth(max(1.8, dividerPixels * 100 / rect.width))
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)

    context.setFillColor(beakColor.cgColor)
    context.fillEllipse(in: CGRect(x: 66, y: 33, width: 6, height: 6))
    context.restoreGState()
}

func render(size: Int) -> NSBitmapImageRep {
    let scale = CGFloat(size) / canvas
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    let inset = (canvas - tile) / 2 * scale
    let tileRect = NSRect(x: inset, y: inset, width: tile * scale, height: tile * scale)
    let squircle = NSBezierPath(
        roundedRect: tileRect,
        xRadius: cornerRadius * scale,
        yRadius: cornerRadius * scale
    )
    NSGradient(starting: fillTop, ending: fillBottom)!.draw(in: squircle, angle: -90)

    let rimInset = rimWidth * scale / 2
    let rimRect = tileRect.insetBy(dx: rimInset, dy: rimInset)
    let rim = NSBezierPath(
        roundedRect: rimRect,
        xRadius: cornerRadius * scale - rimInset,
        yRadius: cornerRadius * scale - rimInset
    )
    rimColor.setStroke()
    rim.lineWidth = rimWidth * scale
    rim.stroke()

    // Tiny ICNS representations need a deliberately larger glyph. macOS can
    // select the 16pt/2x image even when the Dock tile appears much larger;
    // without this optical sizing the compact bust collapses into a thin stem.
    let markScale: CGFloat
    switch size {
    case ...16: markScale = 1.10
    case ...32: markScale = 0.90
    case ...64: markScale = 0.78
    default: markScale = defaultMarkScale
    }
    let markSide = tileRect.width * markScale
    let markRect = CGRect(
        x: tileRect.midX - markSide / 2,
        y: tileRect.midY - markSide / 2,
        width: markSide,
        height: markSide
    )
    drawMark(in: context, rect: markRect)

    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: context.makeImage()!)
}

func write(_ image: NSBitmapImageRep, name: String) throws {
    let data = image.representation(using: .png, properties: [:])!
    try data.write(to: outDir.appendingPathComponent(name))
    print("  \(name)")
}

for (pointSize, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for imageScale in scales {
        let pixelSize = pointSize * imageScale
        let name = imageScale == 1 ? "icon_\(pointSize).png" : "icon_\(pointSize)@2x.png"
        try write(render(size: pixelSize), name: name)
    }
}

print("done → \(outDir.path)")
