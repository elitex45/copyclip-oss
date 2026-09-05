// Renders the app icon (rounded blue square + paperclip) into Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
    let grad = NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
                          ending: NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.75, alpha: 1))!
    grad.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
    if let sym = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        NSColor.white.set()
        sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let s = sym.size
        let scale = (size * 0.55) / max(s.width, s.height)
        let w = s.width * scale, h = s.height * scale
        tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
    }
    img.unlockFocus()
    return img
}

let out = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),
                   ("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = render(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("iconset written")
