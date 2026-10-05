import AppKit
import QuartzCore

/// Floating, click-through-capable panel used for both overlay layers.
private class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The overlay for one pinned window: a click-through panel with the border and glow,
/// plus a panel exactly over the window that shows its live contents while it is in the background.
@MainActor
final class WindowOverlay {
    var onClick: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    private let borderPanel = OverlayPanel()
    private let mirrorPanel = OverlayPanel()
    private let borderLayer = BorderLayer()
    private let mirrorLayer = CALayer()
    private(set) var isMirrorVisible = false

    init() {
        let borderView = NSView()
        borderView.wantsLayer = true
        borderView.layer?.addSublayer(borderLayer)
        borderPanel.contentView = borderView

        let mirrorView = MirrorView()
        mirrorView.wantsLayer = true
        mirrorView.overlay = self
        mirrorLayer.contentsGravity = .resize
        mirrorLayer.isHidden = true
        mirrorView.layer?.addSublayer(mirrorLayer)
        mirrorPanel.contentView = mirrorView
    }

    var isVisible: Bool { borderPanel.isVisible }
    var isOnActiveSpace: Bool { borderPanel.isOnActiveSpace }

    func orderFront() {
        mirrorPanel.orderFrontRegardless()
        borderPanel.orderFrontRegardless()
    }

    func orderOut() {
        borderPanel.orderOut(nil)
        mirrorPanel.orderOut(nil)
    }

    func close() {
        borderPanel.close()
        mirrorPanel.close()
    }

    /// - Parameter windowFrame: frame of the pinned window in AppKit screen coordinates.
    func layout(windowFrame: NSRect, cornerRadius: CGFloat, style: BorderStyle) {
        let outset = style.outset
        let borderFrame = windowFrame.insetBy(dx: -outset, dy: -outset)
        if borderPanel.frame != borderFrame {
            borderPanel.setFrame(borderFrame, display: false)
        }
        if mirrorPanel.frame != windowFrame {
            mirrorPanel.setFrame(windowFrame, display: false)
        }

        let bounds = CGRect(origin: .zero, size: borderFrame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorLayer.frame = CGRect(origin: .zero, size: windowFrame.size)
        mirrorLayer.contentsScale = mirrorPanel.backingScaleFactor
        borderLayer.frame = bounds
        borderLayer.contentsScale = borderPanel.backingScaleFactor
        CATransaction.commit()
        borderLayer.update(windowRect: bounds.insetBy(dx: outset, dy: outset), cornerRadius: cornerRadius, style: style)
    }

    func display(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorLayer.contents = surface
        CATransaction.commit()
    }

    /// The mirror is shown (and catches clicks) only while the real window is not focused.
    func setMirrorVisible(_ visible: Bool) {
        guard visible != isMirrorVisible else { return }
        isMirrorVisible = visible
        mirrorPanel.ignoresMouseEvents = !visible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorLayer.isHidden = !visible
        CATransaction.commit()
    }
}

private final class MirrorView: NSView {
    weak var overlay: WindowOverlay?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { overlay?.onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { overlay?.onClick?() }
    }

    override func scrollWheel(with event: NSEvent) {
        MainActor.assumeIsolated { overlay?.onScroll?(event) }
    }
}
