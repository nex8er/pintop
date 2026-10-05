// Renders the 1024×1024 app icon PNG: a blue rounded square with the mdi-pin glyph.
// Usage: compiled together with Sources/PinTop/SVGPath.swift by scripts/build.sh.
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Cannot create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body centered in a 1024pt canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let background = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(srgbRed: 0.30, green: 0.58, blue: 1.00, alpha: 1),
    ending: NSColor(srgbRed: 0.08, green: 0.30, blue: 0.85, alpha: 1)
)?.draw(in: background, angle: -90)

// SVG coordinates are y-down in a 24×24 box; flip, scale and tilt the pin.
let glyph = SVGPath.bezierPath("M16,12V4H17V2H7V4H8V12L6,14V16H11.2V22H12.8V16H18V14L16,12Z")
var transform = AffineTransform.identity
transform.translate(x: size / 2, y: size / 2)
transform.rotate(byDegrees: -30)
transform.scale(x: 24, y: -24)
transform.translate(x: -12, y: -12)
glyph.transform(using: transform)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor.white.setFill()
glyph.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
try png.write(to: URL(fileURLWithPath: outputPath))
