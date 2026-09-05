// Renders assets/social-preview.png (1280x640) for the GitHub social preview.
// Run: swift scripts/make-social.swift
import AppKit

let W: CGFloat = 1280, H: CGFloat = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// background
NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).set()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// icon (same drawing as the app icon)
let size: CGFloat = 300
let ox: CGFloat = 110, oy: CGFloat = (H - size) / 2
let rect = NSRect(x: ox, y: oy, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
           ending: NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.75, alpha: 1))!.draw(in: path, angle: -90)
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
if let sym = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let scale = (size * 0.55) / max(sym.size.width, sym.size.height)
    let w = sym.size.width * scale, h = sym.size.height * scale
    tinted.draw(in: NSRect(x: ox + (size - w) / 2, y: oy + (size - h) / 2, width: w, height: h))
}

// text
func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    NSAttributedString(string: s, attributes: attrs).draw(at: NSPoint(x: 470, y: y))
}
draw("CopyClip OSS", size: 72, weight: .bold, color: .white, y: 360)
draw("Clipboard history for macOS.", size: 34, weight: .regular, color: NSColor(white: 0.85, alpha: 1), y: 300)
draw("Encrypted on disk. Touch ID or PIN to open.", size: 34, weight: .regular, color: NSColor(white: 0.85, alpha: 1), y: 254)
draw("Locks itself after 60 seconds.", size: 34, weight: .regular, color: NSColor(white: 0.85, alpha: 1), y: 208)
draw("Open source  ·  MIT  ·  github.com/elitex45/copyclip-oss", size: 24, weight: .medium,
     color: NSColor(calibratedRed: 0.45, green: 0.62, blue: 1.0, alpha: 1), y: 140)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/social-preview.png"))
print("written")
