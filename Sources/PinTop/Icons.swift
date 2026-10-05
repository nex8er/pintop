import AppKit

enum Icons {
    /// mdi-pin (F0403)
    static let pinPath = "M16,12V4H17V2H7V4H8V12L6,14V16H11.2V22H12.8V16H18V14L16,12Z"
    /// mdi-pin-off (F0404)
    static let pinOffPath = "M2,5.27L3.28,4L20,20.72L18.73,22L12.8,16.07V22H11.2V16H6V14L8,12V11.27L2,5.27M16,12L18,14V16H17.82L8,6.18V4H7V2H17V4H16V12Z"

    static let pinned = menuBarImage(pinPath, description: "PinTop – windows pinned")
    static let idle = menuBarImage(pinOffPath, description: "PinTop")

    private static func menuBarImage(_ svgPath: String, description: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let path = SVGPath.bezierPath(svgPath)
            path.transform(using: AffineTransform(scale: rect.width / 24))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
