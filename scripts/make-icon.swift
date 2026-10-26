// Draws the app icon and writes Resources/AppIcon.icns.  Run: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824pt body centred on a 1024 canvas, ~185pt corner radius.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.11, blue: 0.20, alpha: 1),
                        NSColor(srgbRed: 0.22, green: 0.16, blue: 0.45, alpha: 1)])!.draw(in: path, angle: 90)

    // Soft glow behind the mouse.
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    let glow = NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.55), .clear])!
    glow.draw(fromCenter: NSPoint(x: 512 * s, y: 470 * s), radius: 0, toCenter: NSPoint(x: 512 * s, y: 470 * s), radius: 420 * s, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    // Mouse symbol.
    let config = NSImage.SymbolConfiguration(pointSize: 470 * s, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let r = NSRect(x: (1024 * s - sym.size.width) / 2, y: (1024 * s - sym.size.height) / 2 - 10 * s,
                       width: sym.size.width, height: sym.size.height)
        sym.draw(in: r)
    }

    // Small "X2" badge.
    let badge = NSRect(x: 600 * s, y: 175 * s, width: 230 * s, height: 120 * s)
    NSColor(srgbRed: 0.35, green: 0.85, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: badge, xRadius: 60 * s, yRadius: 60 * s).fill()
    let text = NSAttributedString(string: "X2", attributes: [
        .font: NSFont.systemFont(ofSize: 84 * s, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.20, alpha: 1),
    ])
    let ts = text.size()
    text.draw(at: NSPoint(x: badge.midX - ts.width / 2, y: badge.midY - ts.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try draw(size: 1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
