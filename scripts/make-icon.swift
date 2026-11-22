import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outputDirectory.appendingPathComponent("LidAwake.iconset", isDirectory: true)
let icns = outputDirectory.appendingPathComponent("LidAwake.icns")
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.removeItem(at: icns)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func makeMaster() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let bounds = NSRect(origin: .zero, size: size)
    let tileRect = bounds.insetBy(dx: 82, dy: 82)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)

    // macOS-style drop shadow behind the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor.black.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    tile.addClip()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.035, green: 0.055, blue: 0.12, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.06, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.18, green: 0.12, blue: 0.40, alpha: 1)
    ])!
    gradient.draw(in: tileRect, angle: -55)

    // Soft top-left glass highlight.
    context.saveGState()
    if let highlight = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.30), 0.0),
        (NSColor.white.withAlphaComponent(0.02), 0.55),
        (NSColor.clear, 1.0)) {
        let highlightRect = NSRect(x: -100, y: 480, width: 900, height: 800)
        highlight.draw(in: NSBezierPath(ovalIn: highlightRect), angle: -35)
    }
    context.restoreGState()

    // Subtle inner border / glass edge.
    let border = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    border.lineWidth = 3
    border.stroke()

    // Crescent moon from the system symbol, tinted warm and drawn cleanly at all sizes.
    let cream = NSColor(srgbRed: 0.96, green: 0.91, blue: 0.74, alpha: 1)
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 560, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [cream]))
    if let moon = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let moonSize = moon.size
        let moonRect = NSRect(
            x: (size.width - moonSize.width) / 2,
            y: 250,
            width: moonSize.width,
            height: moonSize.height
        )
        moon.draw(in: moonRect)
    }

    // A small awake spark.
    let spark = NSBezierPath()
    spark.move(to: NSPoint(x: 760, y: 760))
    spark.line(to: NSPoint(x: 782, y: 824))
    spark.line(to: NSPoint(x: 846, y: 846))
    spark.line(to: NSPoint(x: 782, y: 868))
    spark.line(to: NSPoint(x: 760, y: 932))
    spark.line(to: NSPoint(x: 738, y: 868))
    spark.line(to: NSPoint(x: 674, y: 846))
    spark.line(to: NSPoint(x: 738, y: 824))
    spark.close()
    NSColor(srgbRed: 0.35, green: 0.95, blue: 0.73, alpha: 1).setFill()
    spark.fill()

    // A quiet lid line under the moon.
    let lid = NSBezierPath(roundedRect: NSRect(x: 275, y: 190, width: 474, height: 22),
                           xRadius: 11, yRadius: 11)
    NSColor.white.withAlphaComponent(0.32).setFill()
    lid.fill()

    image.unlockFocus()
    return image
}

let master = makeMaster()
guard let tiff = master.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}

let masterURL = outputDirectory.appendingPathComponent("icon-1024.png")
try png.write(to: masterURL)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in variants {
    let url = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(px)", "\(px)", masterURL.path, "--out", url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fputs("sips failed for \(name)\n", stderr)
        exit(1)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: masterURL)
try? FileManager.default.removeItem(at: iconset)
print(icns.path)
