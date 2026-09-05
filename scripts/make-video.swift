// Renders a ~40s product video to build/video/frames/*.png. Then:
//   ffmpeg -framerate 30 -i build/video/frames/f%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 assets/demo.mp4
import AppKit

let W: CGFloat = 1920, H: CGFloat = 1080, FPS = 30
let bg = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)
let panelBg = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
let blue = NSColor(calibratedRed: 0.30, green: 0.50, blue: 1.0, alpha: 1)
let dim = NSColor(white: 0.75, alpha: 1)

func ease(_ t: CGFloat) -> CGFloat { t < 0 ? 0 : t > 1 ? 1 : t * t * (3 - 2 * t) }
func clamp(_ t: CGFloat) -> CGFloat { max(0, min(1, t)) }

func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
          x: CGFloat, y: CGFloat, alpha: CGFloat = 1, center: Bool = false, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha)])
    let sz = a.size()
    a.draw(at: NSPoint(x: center ? x - sz.width / 2 : x, y: y))
}

func symbol(_ name: String, size: CGFloat, color: NSColor, x: CGFloat, y: CGFloat, alpha: CGFloat = 1) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    let t = NSImage(size: sym.size); t.lockFocus()
    sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.set(); NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop); t.unlockFocus()
    t.draw(in: NSRect(x: x - sym.size.width / 2, y: y - sym.size.height / 2, width: sym.size.width, height: sym.size.height),
           from: .zero, operation: .sourceOver, fraction: alpha)
}

func icon(size: CGFloat, x: CGFloat, y: CGFloat, alpha: CGFloat = 1) {
    let rect = NSRect(x: x, y: y, width: size, height: size)
    let p = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: alpha),
               ending: NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.75, alpha: alpha))!.draw(in: p, angle: -90)
    symbol("paperclip", size: size * 0.5, color: .white, x: x + size / 2, y: y + size / 2, alpha: alpha)
}

/// Draws the app panel (300x? like the real one) scaled up 2.4x.
func panel(x: CGFloat, y: CGFloat, w: CGFloat = 720, h: CGFloat, alpha: CGFloat = 1, body: () -> Void) {
    let r = NSRect(x: x, y: y, width: w, height: h)
    NSColor.black.withAlphaComponent(0.35 * alpha).set()
    NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: -10).insetBy(dx: -6, dy: -6), xRadius: 28, yRadius: 28).fill()
    panelBg.withAlphaComponent(alpha).set()
    NSBezierPath(roundedRect: r, xRadius: 22, yRadius: 22).fill()
    NSColor(white: 1, alpha: 0.08 * alpha).set()
    NSBezierPath(roundedRect: r, xRadius: 22, yRadius: 22).stroke()
    body()
}

func menuBar(alpha: CGFloat = 1) {
    NSColor(white: 0.12, alpha: alpha).set()
    NSRect(x: 0, y: H - 56, width: W, height: 56).fill()
    symbol("paperclip", size: 30, color: NSColor(white: 0.95, alpha: alpha), x: W - 420, y: H - 28)
    symbol("wifi", size: 26, color: NSColor(white: 0.9, alpha: alpha), x: W - 330, y: H - 28)
    symbol("battery.100", size: 28, color: NSColor(white: 0.9, alpha: alpha), x: W - 250, y: H - 28)
    text("Sat 11:42 PM", size: 26, weight: .medium, color: NSColor(white: 0.95, alpha: alpha), x: W - 190, y: H - 42)
}

let clips = ["https://github.com/elitex45/copyclip-oss", "sk-live-••••••••••••  (never stored: concealed)",
             "Meeting moved to 3pm, bring the deck", "git clone git@github.com:elitex45/copyclip-oss", "0x7A3f...c91E",
             "Dear team, quick update on the release", "SELECT count(*) FROM users WHERE active"]

func historyPanel(x: CGFloat, y: CGFloat, shown: Int, secondsFrac: CGFloat, alpha: CGFloat = 1, hover: Int = -1) {
    let rowH: CGFloat = 60, top: CGFloat = 70
    let h = top + rowH * CGFloat(clips.count) + 70
    panel(x: x, y: y, h: h, alpha: alpha) {
        text("Search", size: 28, color: NSColor(white: 0.5, alpha: alpha), x: x + 28, y: y + h - 56)
        NSColor(white: 1, alpha: 0.08 * alpha).set(); NSRect(x: x, y: y + h - top, width: 720, height: 2).fill()
        blue.withAlphaComponent(alpha).set(); NSRect(x: x, y: y + h - top, width: 720 * secondsFrac, height: 4).fill()
        for (i, c) in clips.prefix(shown).enumerated() {
            let ry = y + h - top - rowH * CGFloat(i + 1)
            if i == hover {
                NSColor(white: 1, alpha: 0.10 * alpha).set()
                NSBezierPath(roundedRect: NSRect(x: x + 10, y: ry + 4, width: 700, height: rowH - 8), xRadius: 10, yRadius: 10).fill()
            }
            let shownText = i == 1 ? "(hidden: password manager item)" : c
            text(shownText, size: 26, color: NSColor(white: i == 1 ? 0.45 : 0.95, alpha: alpha), x: x + 28, y: ry + 15)
        }
        let fy = y + 22
        for (i, s) in ["gearshape", "trash"].enumerated() { symbol(s, size: 26, color: dim, x: x + 40 + CGFloat(i) * 50, y: fy + 12, alpha: alpha) }
        for (i, s) in ["lock", "power"].enumerated() { symbol(s, size: 26, color: dim, x: x + 720 - 90 + CGFloat(i) * 50, y: fy + 12, alpha: alpha) }
    }
}

func unlockPanel(x: CGFloat, y: CGFloat, alpha: CGFloat = 1, pulse: CGFloat = 0) {
    panel(x: x, y: y, h: 300, alpha: alpha) {
        symbol("touchid", size: 90 + pulse * 8, color: NSColor(calibratedRed: 1, green: 0.3, blue: 0.5, alpha: alpha), x: x + 360, y: y + 200)
        NSColor(white: 0.1, alpha: alpha).set()
        NSBezierPath(roundedRect: NSRect(x: x + 40, y: y + 50, width: 640, height: 60), xRadius: 12, yRadius: 12).fill()
        text("PIN", size: 28, color: NSColor(white: 0.5, alpha: alpha), x: x + 360, y: y + 63, center: true)
    }
}

// MARK: timeline (seconds)
struct Scene { let start: CGFloat; let dur: CGFloat; let draw: (CGFloat, CGFloat) -> Void } // (t within scene, global alpha)
var scenes: [Scene] = []
var cursor: CGFloat = 0
func add(_ d: CGFloat, _ f: @escaping (CGFloat, CGFloat) -> Void) { scenes.append(Scene(start: cursor, dur: d, draw: f)); cursor += d }

// 1 Title
add(5) { t, a in
    let s = 0.9 + 0.1 * ease(t / 1)
    icon(size: 260 * s, x: W / 2 - 130 * s, y: 600 - 130 * (s - 1), alpha: a * ease(t / 0.8))
    text("CopyClip OSS", size: 96, weight: .bold, x: W / 2, y: 430, alpha: a * ease((t - 0.6) / 0.8), center: true)
    text("A clipboard manager for macOS that keeps your history locked.", size: 40, color: dim, x: W / 2, y: 340, alpha: a * ease((t - 1.2) / 0.8), center: true)
}
// 2 Copy anything
add(7) { t, a in
    menuBar(alpha: a)
    text("Copy anything. It's saved.", size: 72, weight: .bold, x: 140, y: 760, alpha: a * ease(t / 0.6))
    text("Click the paperclip to see your history.", size: 34, color: dim, x: 140, y: 690, alpha: a * ease((t - 0.4) / 0.6))
    text("Click an item to copy it again.", size: 34, color: dim, x: 140, y: 635, alpha: a * ease((t - 0.8) / 0.6))
    let shown = min(clips.count, Int((t - 0.5) / 0.45) + 1)
    let hover = t > 5 ? 2 : -1
    historyPanel(x: W - 720 - 100, y: 200, shown: max(0, shown), secondsFrac: 1, alpha: a * ease(t / 0.5), hover: hover)
}
// 3 Locked
add(7) { t, a in
    text("Locked by Touch ID.", size: 72, weight: .bold, x: 140, y: 760, alpha: a * ease(t / 0.6))
    text("Opening it asks for your fingerprint.", size: 34, color: dim, x: 140, y: 690, alpha: a * ease((t - 0.4) / 0.6))
    text("No Touch ID? Use a PIN.", size: 34, color: dim, x: 140, y: 635, alpha: a * ease((t - 0.8) / 0.6))
    text("The key lives in the Secure Enclave chip.", size: 34, color: dim, x: 140, y: 580, alpha: a * ease((t - 1.2) / 0.6))
    let pulse = CGFloat(abs(sin(Double(t) * 2.5)))
    unlockPanel(x: W - 720 - 100, y: 420, alpha: a * ease(t / 0.5), pulse: pulse)
}
// 4 Encrypted
add(7) { t, a in
    text("Encrypted on disk.", size: 72, weight: .bold, x: 140, y: 760, alpha: a * ease(t / 0.6))
    text("AES-256-GCM. No other app or script", size: 34, color: dim, x: 140, y: 690, alpha: a * ease((t - 0.4) / 0.6))
    text("can read it. Not even this app, while locked.", size: 34, color: dim, x: 140, y: 635, alpha: a * ease((t - 0.6) / 0.6))
    // hex dump mock
    panel(x: W - 720 - 100, y: 330, h: 420, alpha: a * ease((t - 0.8) / 0.6)) {
        text("vault.enc", size: 26, weight: .semibold, color: dim, x: W - 720 - 100 + 28, y: 700, alpha: a, mono: true)
        var rng = SystemRandomNumberGenerator()
        srand48(7)
        for r in 0..<9 {
            var line = ""
            for _ in 0..<15 { line += String(format: "%02x ", Int(drand48() * 256)) }
            let visible = clamp((t - 1.0 - CGFloat(r) * 0.15) / 0.3)
            text(line, size: 22, color: NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.6, alpha: 1), x: W - 720 - 100 + 28, y: 650 - CGFloat(r) * 36, alpha: a * visible, mono: true)
        }
        _ = rng.next()
    }
}
// 5 60 seconds
add(7) { t, a in
    text("Locks itself after 60 seconds.", size: 72, weight: .bold, x: 140, y: 760, alpha: a * ease(t / 0.6))
    text("It forgets the key and wipes memory.", size: 34, color: dim, x: 140, y: 690, alpha: a * ease((t - 0.4) / 0.6))
    text("New copies are still saved while locked.", size: 34, color: dim, x: 140, y: 635, alpha: a * ease((t - 0.8) / 0.6))
    let frac = 1 - clamp((t - 0.8) / 4.5)
    if t < 5.6 {
        historyPanel(x: W - 720 - 100, y: 200, shown: clips.count, secondsFrac: frac, alpha: a * ease(t / 0.5))
    } else {
        unlockPanel(x: W - 720 - 100, y: 420, alpha: a * ease((t - 5.6) / 0.4))
    }
    let secs = Int(60 * frac)
    text("\(secs)s", size: 120, weight: .bold, color: blue, x: 260, y: 300, alpha: a * ease((t - 0.8) / 0.5))
}
// 6 Install
add(6) { t, a in
    text("Free and open source.", size: 72, weight: .bold, x: W / 2, y: 780, alpha: a * ease(t / 0.6), center: true)
    let steps = ["1.  Download the DMG from GitHub", "2.  Drag it to Applications", "3.  Click the paperclip, pick a PIN, done"]
    for (i, s) in steps.enumerated() {
        text(s, size: 44, color: .white, x: 560, y: 600 - CGFloat(i) * 90, alpha: a * ease((t - 0.6 - CGFloat(i) * 0.5) / 0.5))
    }
    text("MIT licensed. Small, auditable crypto. PRs welcome.", size: 34, color: dim, x: W / 2, y: 240, alpha: a * ease((t - 2.5) / 0.6), center: true)
}
// 7 End
add(4) { t, a in
    icon(size: 200, x: W / 2 - 100, y: 600, alpha: a * ease(t / 0.5))
    text("github.com/elitex45/copyclip-oss", size: 56, weight: .semibold, color: blue, x: W / 2, y: 480, alpha: a * ease((t - 0.4) / 0.6), center: true)
}

let total = cursor
let frames = Int(total * CGFloat(FPS))
let dir = URL(fileURLWithPath: "build/video/frames")
try? FileManager.default.removeItem(at: dir)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let fade: CGFloat = 0.5
for f in 0..<frames {
    let time = CGFloat(f) / CGFloat(FPS)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    bg.set(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    for s in scenes where time >= s.start && time < s.start + s.dur {
        let t = time - s.start
        let a = min(ease(t / fade), ease((s.dur - t) / fade))
        s.draw(t, a)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(String(format: "f%05d.png", f)))
    if f % 300 == 0 { print("frame \(f)/\(frames)") }
}
print("done \(frames) frames, \(total)s")
