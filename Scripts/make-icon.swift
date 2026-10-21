import AppKit

let canvas: CGFloat = 1024
let ink = NSColor(red: 0.31, green: 0.36, blue: 0.94, alpha: 1)

func roundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: rounded, size: size) ?? base
}

func fillBubble(_ rect: NSRect, tail: [NSPoint], alpha: CGFloat) {
    let context = NSGraphicsContext.current!.cgContext
    context.setAlpha(alpha)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 92, yRadius: 92).fill()
    let pointer = NSBezierPath()
    pointer.move(to: tail[0])
    tail.dropFirst().forEach { pointer.line(to: $0) }
    pointer.close()
    pointer.fill()
    context.endTransparencyLayer()
    context.setAlpha(1)
}

func drawGlyph(_ glyph: String, in rect: NSRect, size: CGFloat, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: roundedFont(size), .foregroundColor: color]
    let text = NSAttributedString(string: glyph, attributes: attributes)
    let bounds = text.size()
    text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
}

func drawBody() {
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    let top = NSColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1)
    let bottom = NSColor(red: 0.42, green: 0.25, blue: 0.94, alpha: 1)
    NSGradient(starting: bottom, ending: top)?.draw(in: body, angle: 90)
}

func drawBubbles() {
    let back = NSRect(x: 400, y: 470, width: 380, height: 300)
    fillBubble(back, tail: [NSPoint(x: 650, y: 520), NSPoint(x: 740, y: 520), NSPoint(x: 770, y: 410)], alpha: 0.32)
    drawGlyph("文", in: back, size: 170, color: .white)

    let front = NSRect(x: 244, y: 254, width: 380, height: 300)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    fillBubble(front, tail: [NSPoint(x: 274, y: 304), NSPoint(x: 374, y: 304), NSPoint(x: 254, y: 194)], alpha: 1)
    NSGraphicsContext.restoreGraphicsState()
    drawGlyph("A", in: front, size: 200, color: ink)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / canvas
    NSAffineTransform(transform: AffineTransform(scale: scale)).concat()
    drawBody()
    drawBubbles()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

if CommandLine.arguments.count > 2 {
    try render(pixels: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
