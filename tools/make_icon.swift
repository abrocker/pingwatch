// Renders the PingWatch app icon.  Usage: swift tools/make_icon.swift Resources/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 188, yRadius: 188)
    let center = CGPoint(x: 512, y: 520)

    // Tile with soft drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: color(0, 0, 0, 0.4).cgColor)
    color(0.04, 0.08, 0.18).setFill()
    shape.fill()
    ctx.restoreGState()

    ctx.saveGState()
    shape.addClip()

    // Deep blue background.
    NSGradient(colors: [color(0.10, 0.20, 0.42), color(0.03, 0.07, 0.17)])!.draw(in: tile, angle: -70)

    // Radar glow behind the rings.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0.15, 0.85, 0.95, 0.45).cgColor, color(0.15, 0.85, 0.95, 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 400, options: [])

    // Ping rings.
    for (i, radius) in [95.0, 185, 275, 365].enumerated() {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
        ring.lineWidth = 12
        color(0.35, 0.95, 1, [0.85, 0.55, 0.32, 0.16][i]).setStroke()
        ring.stroke()
    }

    // Latency trace with a glowing spike.
    let trace = NSBezierPath()
    let points: [CGPoint] = [
        CGPoint(x: 150, y: 500), CGPoint(x: 335, y: 500), CGPoint(x: 395, y: 500),
        CGPoint(x: 440, y: 650), CGPoint(x: 500, y: 330), CGPoint(x: 560, y: 720),
        CGPoint(x: 615, y: 470), CGPoint(x: 655, y: 520), CGPoint(x: 700, y: 520), CGPoint(x: 880, y: 520),
    ]
    trace.move(to: points[0])
    points.dropFirst().forEach { trace.line(to: $0) }
    trace.lineWidth = 26
    trace.lineCapStyle = .round
    trace.lineJoinStyle = .round

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: color(0.2, 1, 0.55, 0.9).cgColor)
    color(0.3, 1, 0.6).setStroke()
    trace.stroke()
    ctx.restoreGState()
    color(0.85, 1, 0.9).setStroke()
    trace.lineWidth = 8
    trace.stroke()

    // Glass highlight across the top.
    NSGradient(colors: [color(1, 1, 1, 0.28), color(1, 1, 1, 0)])!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    ctx.restoreGState()

    // Thin inner edge.
    let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 186, yRadius: 186)
    edge.lineWidth = 4
    color(1, 1, 1, 0.22).setStroke()
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ master: NSBitmapImageRep, pixels: Int, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

let master = renderMaster()
for base in [16, 32, 128, 256, 512] {
    write(master, pixels: base, name: "icon_\(base)x\(base).png")
    write(master, pixels: base * 2, name: "icon_\(base)x\(base)@2x.png")
}
