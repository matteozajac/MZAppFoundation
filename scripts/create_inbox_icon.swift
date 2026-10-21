#!/usr/bin/env swift
// Original MZ Inbox artwork, distributed under the repository MIT license.
// Drawn from geometric paths; no system or third-party artwork is extracted.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let artwork = root.appendingPathComponent("Tools/MZInboxMac/Artwork", isDirectory: true)
let iconset = root.appendingPathComponent("output/inbox/AppIcon.iconset", isDirectory: true)
let files = FileManager.default
try files.createDirectory(at: artwork, withIntermediateDirectories: true)
try files.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawRabbit(in rect: NSRect, template: Bool) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.minY)
    transform.scaleX(by: rect.width / 100, yBy: rect.height / 100)
    transform.concat()
    NSColor.white.setFill()
    // Two ears and a broad face form an original geometric rabbit silhouette.
    NSBezierPath(ovalIn: NSRect(x: 22, y: 45, width: 23, height: 53)).fill()
    NSBezierPath(ovalIn: NSRect(x: 55, y: 45, width: 23, height: 53)).fill()
    NSBezierPath(ovalIn: NSRect(x: 9, y: 3, width: 82, height: 65)).fill()
    if template {
        NSGraphicsContext.current?.compositingOperation = .destinationOut
    } else {
        NSColor(srgbRed: 247 / 255, green: 92 / 255, blue: 106 / 255, alpha: 1).setFill()
    }
    NSBezierPath(ovalIn: NSRect(x: 30, y: 30, width: 8, height: 10)).fill()
    NSBezierPath(ovalIn: NSRect(x: 62, y: 30, width: 8, height: 10)).fill()
    let nose = NSBezierPath()
    nose.move(to: NSPoint(x: 44, y: 23))
    nose.line(to: NSPoint(x: 56, y: 23))
    nose.line(to: NSPoint(x: 50, y: 17))
    nose.close()
    nose.fill()
}

func png(size: Int, appIcon: Bool) throws -> Data {
    let side = CGFloat(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let background = NSRect(x: side / 16, y: side / 16, width: side * 7 / 8, height: side * 7 / 8)
    if appIcon {
        let plate = NSBezierPath(roundedRect: background, xRadius: side * 0.19, yRadius: side * 0.19)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = side * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
        shadow.set()
        NSColor.white.setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Original coral palette in sRGB.
        let top = NSColor(srgbRed: 248 / 255, green: 105 / 255, blue: 119 / 255, alpha: 1)
        let bottom = NSColor(srgbRed: 247 / 255, green: 86 / 255, blue: 100 / 255, alpha: 1)
        NSGradient(starting: top, ending: bottom)!.draw(in: plate, angle: 270)
    }
    let sideInset = appIcon ? side * 0.19 : side * 0.04
    let rabbitRect = NSRect(x: sideInset, y: sideInset,
                            width: side - sideInset * 2, height: side - sideInset * 2)
    drawRabbit(in: rabbitRect, template: !appIcon)
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(size: points * scale, appIcon: true).write(to: iconset.appendingPathComponent(name))
    }
}
try png(size: 1024, appIcon: true).write(to: artwork.appendingPathComponent("AppIcon.png"))
try png(size: 128, appIcon: false).write(to: artwork.appendingPathComponent("RabbitTemplate.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["--convert", "icns", "--output", artwork.appendingPathComponent("AppIcon.icns").path, iconset.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Created original rabbit app and menu bar artwork in \(artwork.path)")
