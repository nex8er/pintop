import AppKit
import QuartzCore

struct BorderStyle: Equatable {
    var width: CGFloat
    var opacity: CGFloat
    var color: NSColor
    /// Second gradient color; nil draws a solid border.
    var gradientColor: NSColor?
    /// 0 disables the glow.
    var glow: CGFloat
    var animated: Bool

    var glowRadius: CGFloat { glow > 0 ? 3 + glow * 15 : 0 }

    /// Room needed around the window so neither the border nor its glow is clipped.
    var outset: CGFloat { width + (glow > 0 ? ceil(glowRadius * 2) : 0) }

    /// Fallback until the real radius is measured from the window's pixels.
    static let defaultCornerRadius: CGFloat =
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) ? 16 : 10
}

/// Draws a gradient border with an outer glow around a rounded window rectangle.
final class BorderLayer: CALayer {
    private static let animationKey = "rotate"

    private let glowContainer = CALayer()
    private let glowLayer = CALayer()
    private let glowMask = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let strokeMask = CAShapeLayer()

    override init() {
        super.init()
        // The glow lives in a masked container: masking the shadow-casting layer itself would clip the shadow.
        glowLayer.shadowOffset = .zero
        glowContainer.addSublayer(glowLayer)
        glowMask.fillRule = .evenOdd
        glowContainer.mask = glowMask
        addSublayer(glowContainer)

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        strokeMask.fillColor = nil
        strokeMask.strokeColor = NSColor.black.cgColor
        gradientLayer.mask = strokeMask
        addSublayer(gradientLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter windowRect: the window's rectangle in this layer's coordinate space.
    func update(windowRect: CGRect, cornerRadius: CGFloat, style: BorderStyle) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        opacity = Float(style.opacity)

        let strokeRect = windowRect.insetBy(dx: -style.width / 2, dy: -style.width / 2)
        let strokePath = Self.roundedPath(strokeRect, radius: cornerRadius + style.width / 2)

        gradientLayer.frame = bounds
        strokeMask.frame = bounds
        strokeMask.path = strokePath
        strokeMask.lineWidth = style.width
        let start = style.color.cgColor
        let end = (style.gradientColor ?? style.color).cgColor
        gradientLayer.colors = [start, end, start]

        glowContainer.isHidden = style.glow <= 0
        if style.glow > 0 {
            glowContainer.frame = bounds
            glowLayer.frame = bounds
            glowLayer.shadowPath = strokePath.copy(strokingWithWidth: style.width, lineCap: .butt, lineJoin: .round, miterLimit: 10)
            glowLayer.shadowColor = Self.blend(style.color, style.gradientColor).cgColor
            glowLayer.shadowRadius = style.glowRadius
            glowLayer.shadowOpacity = Float(0.35 + style.glow * 0.65)
            // Keep the glow outside the window so it never tints the window's contents.
            let mask = CGMutablePath()
            mask.addRect(bounds)
            mask.addPath(Self.roundedPath(windowRect, radius: cornerRadius))
            glowMask.frame = bounds
            glowMask.path = mask
        }

        if style.animated {
            if gradientLayer.animation(forKey: Self.animationKey) == nil {
                gradientLayer.add(Self.rotationAnimation(), forKey: Self.animationKey)
            }
        } else {
            gradientLayer.removeAnimation(forKey: Self.animationKey)
        }
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func blend(_ color: NSColor, _ other: NSColor?) -> NSColor {
        guard let other else { return color }
        return color.blended(withFraction: 0.5, of: other) ?? color
    }

    /// Spins the conic gradient by moving its end point around the center.
    private static func rotationAnimation() -> CAAnimation {
        let steps = 72
        let values = (0...steps).map { step -> NSValue in
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            return NSValue(point: NSPoint(x: 0.5 + 0.5 * sin(angle), y: 0.5 - 0.5 * cos(angle)))
        }
        let animation = CAKeyframeAnimation(keyPath: "endPoint")
        animation.values = values
        animation.duration = 4
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}
