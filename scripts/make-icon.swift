import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let scratch = outputDirectory.appendingPathComponent(".icon-\(UUID().uuidString)", isDirectory: true)
let icns = outputDirectory.appendingPathComponent("LidAwake.icns")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

func makeMaster() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()

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

    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.07, green: 0.66, blue: 0.77, alpha: 1),
        ending: NSColor(srgbRed: 0.04, green: 0.13, blue: 0.37, alpha: 1)
    )!
    gradient.draw(in: tileRect, angle: -55)

    let rim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 4, dy: 4),
                           xRadius: 206, yRadius: 206)
    NSColor.white.withAlphaComponent(0.25).setStroke()
    rim.lineWidth = 8
    rim.stroke()

    // Keep the same laptop silhouette as the menu bar item, with a lit display.
    let screenRect = NSRect(x: 255, y: 354, width: 514, height: 356)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: 42, yRadius: 42)
    NSGradient(
        starting: NSColor(srgbRed: 0.10, green: 0.38, blue: 0.57, alpha: 1),
        ending: NSColor(srgbRed: 0.01, green: 0.15, blue: 0.31, alpha: 1)
    )?.draw(in: screen, angle: -90)
    NSColor(srgbRed: 0.84, green: 0.97, blue: 1.0, alpha: 1).setStroke()
    screen.lineWidth = 36
    screen.stroke()

    let base = NSBezierPath(roundedRect: NSRect(x: 187, y: 270, width: 650, height: 48),
                            xRadius: 24, yRadius: 24)
    NSGradient(
        starting: .white,
        ending: NSColor(srgbRed: 0.52, green: 0.78, blue: 0.93, alpha: 1)
    )?.draw(in: base, angle: -90)

    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 555, y: 638))
    bolt.line(to: NSPoint(x: 422, y: 481))
    bolt.line(to: NSPoint(x: 502, y: 481))
    bolt.line(to: NSPoint(x: 475, y: 384))
    bolt.line(to: NSPoint(x: 602, y: 540))
    bolt.line(to: NSPoint(x: 520, y: 540))
    bolt.close()
    NSColor(srgbRed: 0.54, green: 1.0, blue: 0.82, alpha: 1).setFill()
    bolt.fill()

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

let masterURL = scratch.appendingPathComponent("icon-1024.png")
try png.write(to: masterURL)

// Each ICNS element has a four-byte type, a big-endian length that includes
// its eight-byte header, and a PNG payload at the type's native pixel size.
let variants = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64),
    ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)
]

func element(_ type: String, payload: Data) -> Data {
    var length = UInt32(payload.count + 8).bigEndian
    var data = Data(type.utf8)
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}

var payload = Data()
for (type, pixels) in variants {
    let url = scratch.appendingPathComponent("\(pixels).png")
    if !FileManager.default.fileExists(atPath: url.path) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-z", "\(pixels)", "\(pixels)", masterURL.path, "--out", url.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
    payload.append(element(type, payload: try Data(contentsOf: url)))
}

try element("icns", payload: payload).write(to: icns, options: .atomic)
print(icns.path)
