#!/usr/bin/env swift
import AppKit
import Foundation

/// Generate aTerm app icon: dark rounded terminal window with a glowing prompt cursor and AI sparkle
func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let inset: CGFloat = s * 0.08
    let cornerRadius: CGFloat = s * 0.22
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)

    // Background: dark gradient
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors: [CGFloat] = [
        0.08, 0.08, 0.12, 1.0,   // top: very dark blue-black
        0.04, 0.04, 0.08, 1.0,   // bottom: near black
    ]
    if let gradient = CGGradient(colorSpace: colorSpace, colorComponents: gradColors, locations: [0, 1], count: 2) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: s - inset), end: CGPoint(x: s/2, y: inset), options: [])
    }

    // Subtle border glow
    ctx.resetClip()
    ctx.setLineWidth(s * 0.012)
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.3))
    ctx.strokePath()

    // Title bar dots (traffic lights)
    let dotY = s - inset - s * 0.12
    let dotRadius = s * 0.022
    let dotStartX = inset + s * 0.08
    let dotSpacing = s * 0.05

    for (i, color) in [(0.95, 0.3, 0.3), (0.95, 0.8, 0.2), (0.3, 0.85, 0.35)].enumerated() {
        let cx = dotStartX + CGFloat(i) * dotSpacing
        ctx.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }

    // Terminal prompt: ">" character with glow
    let promptFont = NSFont.monospacedSystemFont(ofSize: s * 0.32, weight: .bold)
    let promptColor = NSColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1.0)

    // Glow behind prompt
    let glowCenter = CGPoint(x: s * 0.32, y: s * 0.42)
    let glowRadius = s * 0.18
    let glowColors: [CGFloat] = [
        0.2, 0.6, 1.0, 0.25,
        0.2, 0.6, 1.0, 0.0,
    ]
    if let glowGradient = CGGradient(colorSpace: colorSpace, colorComponents: glowColors, locations: [0, 1], count: 2) {
        ctx.drawRadialGradient(glowGradient, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: glowRadius, options: [])
    }

    // Draw ">"
    let promptStr = NSAttributedString(string: ">_", attributes: [
        .font: promptFont,
        .foregroundColor: promptColor,
    ])
    let promptSize = promptStr.size()
    let promptOrigin = CGPoint(x: s * 0.18, y: s * 0.28)
    promptStr.draw(at: promptOrigin)

    // AI sparkle element (small diamond/star shape, upper right)
    let sparkleX = s * 0.72
    let sparkleY = s * 0.62
    let sparkleSize = s * 0.08

    ctx.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 0.9))
    // 4-pointed star
    ctx.move(to: CGPoint(x: sparkleX, y: sparkleY + sparkleSize))
    ctx.addLine(to: CGPoint(x: sparkleX + sparkleSize * 0.3, y: sparkleY + sparkleSize * 0.3))
    ctx.addLine(to: CGPoint(x: sparkleX + sparkleSize, y: sparkleY))
    ctx.addLine(to: CGPoint(x: sparkleX + sparkleSize * 0.3, y: sparkleY - sparkleSize * 0.3))
    ctx.addLine(to: CGPoint(x: sparkleX, y: sparkleY - sparkleSize))
    ctx.addLine(to: CGPoint(x: sparkleX - sparkleSize * 0.3, y: sparkleY - sparkleSize * 0.3))
    ctx.addLine(to: CGPoint(x: sparkleX - sparkleSize, y: sparkleY))
    ctx.addLine(to: CGPoint(x: sparkleX - sparkleSize * 0.3, y: sparkleY + sparkleSize * 0.3))
    ctx.closePath()
    ctx.fillPath()

    // Small secondary sparkle
    let s2x = s * 0.82, s2y = s * 0.72, s2s = s * 0.04
    ctx.setFillColor(CGColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 0.7))
    ctx.move(to: CGPoint(x: s2x, y: s2y + s2s))
    ctx.addLine(to: CGPoint(x: s2x + s2s * 0.3, y: s2y + s2s * 0.3))
    ctx.addLine(to: CGPoint(x: s2x + s2s, y: s2y))
    ctx.addLine(to: CGPoint(x: s2x + s2s * 0.3, y: s2y - s2s * 0.3))
    ctx.addLine(to: CGPoint(x: s2x, y: s2y - s2s))
    ctx.addLine(to: CGPoint(x: s2x - s2s * 0.3, y: s2y - s2s * 0.3))
    ctx.addLine(to: CGPoint(x: s2x - s2s, y: s2y))
    ctx.addLine(to: CGPoint(x: s2x - s2s * 0.3, y: s2y + s2s * 0.3))
    ctx.closePath()
    ctx.fillPath()

    // Faint terminal text lines (decoration)
    let lineFont = NSFont.monospacedSystemFont(ofSize: s * 0.065, weight: .regular)
    let lineColor = NSColor(white: 1.0, alpha: 0.12)
    let lines = ["$ ssh deploy@prod", "  connecting...", "  ready."]
    for (i, text) in lines.enumerated() {
        let lineStr = NSAttributedString(string: text, attributes: [
            .font: lineFont,
            .foregroundColor: lineColor,
        ])
        lineStr.draw(at: CGPoint(x: s * 0.18, y: s * 0.12 + CGFloat(i) * s * 0.065))
    }

    image.unlockFocus()
    return image
}

// Generate iconset
let iconsetPath = "/Users/warner/Dev/projects/aTerm/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let image = generateIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("Generated \(name).png (\(size)x\(size))")
}

print("Iconset created at \(iconsetPath)")
print("Run: iconutil -c icns AppIcon.iconset")
