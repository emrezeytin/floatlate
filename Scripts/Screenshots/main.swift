import AppKit
import SwiftUI

let sample = "Bonjour à tous ! La réunion de demain est déplacée à 15 h. Merci d'apporter vos notes sur le nouveau projet et vos idées pour le lancement."
let windowSize = NSSize(width: 440, height: 540)
let margin: CGFloat = 64
let cornerRadius: CGFloat = 16

@MainActor
func spin(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
func snapshot(_ appearance: NSAppearance.Name, text: String) -> NSImage {
    let translator = Translator()
    translator.highQuality = true
    let panel = FloatingPanel(rootView: ContentView(translator: translator) {})
    panel.appearance = NSAppearance(named: appearance)
    panel.setFrame(NSRect(origin: NSPoint(x: -4000, y: -4000), size: windowSize), display: false)
    panel.orderFrontRegardless()
    spin(1.5)
    if !text.isEmpty {
        translator.input = text
        spin(8)
    }

    let frameView = panel.contentView!.superview!
    let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)!
    frameView.cacheDisplay(in: frameView.bounds, to: rep)
    panel.orderOut(nil)

    let image = NSImage(size: frameView.bounds.size)
    image.addRepresentation(rep)
    return image
}

func drawWindow(_ image: NSImage, in rect: NSRect) {
    let shape = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.25).setStroke()
    shape.lineWidth = 1
    shape.stroke()
}

func compose(_ images: [NSImage], to url: URL) throws {
    let size = NSSize(
        width: margin * CGFloat(images.count + 1) + windowSize.width * CGFloat(images.count),
        height: windowSize.height + margin * 2
    )
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let top = NSColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 1)
    let bottom = NSColor(red: 0.56, green: 0.42, blue: 0.96, alpha: 1)
    NSGradient(starting: bottom, ending: top)?.draw(in: NSRect(origin: .zero, size: size), angle: 60)
    for (index, image) in images.enumerated() {
        let x = margin + CGFloat(index) * (windowSize.width + margin)
        drawWindow(image, in: NSRect(origin: NSPoint(x: x, y: margin), size: windowSize))
    }
    NSGraphicsContext.restoreGraphicsState()

    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let images = [snapshot(.aqua, text: sample), snapshot(.darkAqua, text: "")]
    try compose(images, to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
