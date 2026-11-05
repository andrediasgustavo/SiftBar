#!/usr/bin/env swift
import AppKit
import Foundation

// Generates SiftBar.icns from a vector-style drawing at every required size.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let unit = CGFloat(size) / 1024

    // Transparent canvas, then the macOS-style rounded square with a soft shadow.
    let inset = 92 * unit
    let content = NSRect(
        x: inset,
        y: inset,
        width: CGFloat(size) - inset * 2,
        height: CGFloat(size) - inset * 2
    )
    let radius = 195 * unit

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -22 * unit),
        blur: 38 * unit,
        color: NSColor.black.withAlphaComponent(0.38).cgColor
    )

    let squircle = NSBezierPath(roundedRect: content, xRadius: radius, yRadius: radius)
    color(0x2563EB).setFill()
    squircle.fill()
    context.restoreGState()

    // Blue to teal gradient, clipped to the rounded square.
    context.saveGState()
    squircle.addClip()
    let gradient = NSGradient(colors: [color(0x4F8EF7), color(0x0D9488)])!
    gradient.draw(in: content, angle: -45)
    context.restoreGState()

    // A faint inner edge keeps the icon crisp on light backgrounds.
    let border = NSBezierPath(
        roundedRect: content.insetBy(dx: 2 * unit, dy: 2 * unit),
        xRadius: radius - 2 * unit,
        yRadius: radius - 2 * unit
    )
    border.lineWidth = 3 * unit
    color(0xFFFFFF, alpha: 0.18).setStroke()
    border.stroke()

    // Three descending bars: a simple, legible "sift/filter" mark.
    let bars: [(width: CGFloat, y: CGFloat)] = [
        (0.50, 0.655),
        (0.32, 0.515),
        (0.16, 0.375)
    ]
    let barHeight: CGFloat = 0.064
    let contentWidth = content.width
    let contentHeight = content.height

    for bar in bars {
        let width = contentWidth * bar.width
        let height = contentHeight * barHeight
        let rect = NSRect(
            x: content.midX - width / 2,
            y: content.minY + contentHeight * bar.y,
            width: width,
            height: height
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        color(0xFFFFFF, alpha: 0.97).setFill()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// `NSBitmapImageRep` writes RGBA PNGs that `iconutil` rejects; re-encoding
/// through `sips` into a separate file attaches the color profile it expects.
func normalizePNG(from source: URL, to destination: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-s", "format", "png", source.path, "--out", destination.path]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fatalError("Could not normalize \(source.lastPathComponent): \(error)")
    }

    guard process.terminationStatus == 0 else {
        fatalError("sips failed for \(source.lastPathComponent)")
    }
}

let fileManager = FileManager.default
let keepIconset = ProcessInfo.processInfo.environment["SIFTBAR_KEEP_ICONSET"] == "1"
let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("SiftBar.iconset-\(UUID().uuidString)", isDirectory: true)
let raw = workspace.appendingPathComponent("raw", isDirectory: true)
let iconset = workspace.appendingPathComponent("SiftBar.iconset", isDirectory: true)
try fileManager.createDirectory(at: raw, withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer {
    if !keepIconset {
        try? fileManager.removeItem(at: workspace)
    }
}
print("Iconset: \(iconset.path)")

let names: [Int: [String]] = [
    16: ["icon_16x16.png"],
    32: ["icon_16x16@2x.png", "icon_32x32.png"],
    64: ["icon_32x32@2x.png"],
    128: ["icon_128x128.png"],
    256: ["icon_128x128@2x.png", "icon_256x256.png"],
    512: ["icon_256x256@2x.png", "icon_512x512.png"],
    1024: ["icon_512x512@2x.png"]
]

for size in sizes {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(size)px icon")
    }

    for name in names[size] ?? [] {
        let rawFile = raw.appendingPathComponent(name)
        let iconFile = iconset.appendingPathComponent(name)
        try data.write(to: rawFile)
        normalizePNG(from: rawFile, to: iconFile)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}

print("Wrote \(output)")
