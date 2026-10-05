import AppKit
import ApplicationServices

/// A window kept on top: owns its overlay panel, the live capture and the AX observer.
@MainActor
final class PinnedWindow {
    let pid: pid_t
    let windowID: CGWindowID
    let appName: String
    private(set) var title: String

    /// Asks the manager to refresh; `true` means focus may have changed.
    var onNeedsRefresh: ((Bool) -> Void)?
    var onClose: ((PinnedWindow) -> Void)?

    private let app: AXUIElement
    private let window: AXUIElement
    private let overlay = WindowOverlay()
    private let capture = WindowCapture()
    private var observer: AXObserver?
    private var isTargetFocused = false
    private var isClosed = false
    /// Last known bounds in top-left-origin coordinates.
    private var bounds: CGRect = .null
    private var capturedSize: CGSize = .zero
    /// Measured from the captured frames; starts with the system's typical radius.
    private var cornerRadius = BorderStyle.defaultCornerRadius
    private var resizeWorkItem: DispatchWorkItem?

    init(target: WindowTarget) {
        pid = target.pid
        windowID = target.windowID
        appName = target.appName
        app = target.app
        window = target.window
        title = AX.title(of: target.window) ?? ""
    }

    var displayName: String {
        title.isEmpty || title == appName ? appName : "\(appName) — \(title)"
    }

    func start() async throws {
        overlay.onClick = { [weak self] in self?.focusTarget() }
        overlay.onScroll = { [weak self] event in self?.forwardScroll(event) }
        capture.onFrame = { [weak self] surface, radius in self?.handleFrame(surface, cornerRadiusInPixels: radius) }
        capture.onStop = { [weak self] _ in self?.close() }

        guard let info = WindowServer.info(for: [windowID])[windowID] else { throw CaptureError.windowNotFound }
        bounds = info.bounds
        capturedSize = info.bounds.size
        try await capture.start(windowID: windowID, size: info.bounds.size, scale: scaleFactor(for: info.bounds))
        guard !isClosed else {
            capture.stop() // Unpinned while the stream was starting.
            return
        }
        installObserver()
        updateFocusState()
        update(with: WindowServer.info(for: [windowID])[windowID])
    }

    /// Tears everything down. Safe to call more than once.
    func stop() {
        isClosed = true
        resizeWorkItem?.cancel()
        removeObserver()
        capture.stop()
        overlay.orderOut()
        overlay.close()
    }

    func updateFocusState() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = AX.focusedWindow(of: app) else {
            isTargetFocused = false
            return
        }
        isTargetFocused = AX.windowID(of: focused) == windowID
    }

    /// Syncs the overlay with the window's current state as reported by the window server.
    func update(with info: WindowServerInfo?) {
        guard !isClosed else { return }
        guard let info else {
            close() // The window no longer exists.
            return
        }
        guard info.isOnScreen else {
            overlay.orderOut() // Minimized, hidden or on another Space.
            return
        }
        if info.bounds != bounds {
            bounds = info.bounds
            layout()
            scheduleCaptureResize()
        }
        overlay.setMirrorVisible(!isTargetFocused)
        if !overlay.isVisible || !overlay.isOnActiveSpace {
            // Ordering out and back in moves the panel to the Space that is active now.
            overlay.orderOut()
            layout()
            overlay.orderFront()
        }
    }

    func applyAppearance() {
        guard !bounds.isNull else { return }
        layout()
    }

    // MARK: - Private

    private func close() {
        guard !isClosed else { return }
        onClose?(self)
    }

    private func layout() {
        overlay.layout(
            windowFrame: WindowServer.appKitRect(fromTopLeft: bounds),
            cornerRadius: cornerRadius,
            style: AppSettings.shared.borderStyle
        )
    }

    private func handleFrame(_ surface: IOSurface, cornerRadiusInPixels: CGFloat?) {
        overlay.display(surface)
        guard let pixels = cornerRadiusInPixels, !bounds.isNull, bounds.width > 0, surface.width > 0 else { return }
        let points = (pixels * bounds.width / CGFloat(surface.width)).rounded()
        if abs(points - cornerRadius) >= 1 {
            cornerRadius = points
            layout()
        }
    }

    private func scaleFactor(for rect: CGRect) -> CGFloat {
        let appKitRect = WindowServer.appKitRect(fromTopLeft: rect)
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(appKitRect).area < rhs.frame.intersection(appKitRect).area
        }
        return screen?.backingScaleFactor ?? 2
    }

    /// Resizing the stream is relatively expensive, so it is debounced during live resizes.
    private func scheduleCaptureResize() {
        guard bounds.size != capturedSize else { return }
        resizeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isClosed else { return }
            self.capturedSize = self.bounds.size
            self.capture.update(size: self.bounds.size, scale: self.scaleFactor(for: self.bounds))
        }
        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func focusTarget() {
        AX.focus(window: window, app: app, pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onNeedsRefresh?(true)
        }
    }

    /// Delivers scroll events over the mirror straight to the pinned window's process.
    private func forwardScroll(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent?.copy() else { return }
        cgEvent.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        cgEvent.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        cgEvent.postToPid(pid)
    }

    // MARK: - Accessibility notifications

    private func installObserver() {
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(observer, app, notification as CFString, refcon)
        }
        for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                             kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
                             kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, window, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = observer
    }

    private func removeObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
    }

    fileprivate func handle(notification: String) {
        guard !isClosed else { return }
        switch notification {
        case kAXTitleChangedNotification:
            title = AX.title(of: window) ?? title
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            onNeedsRefresh?(true)
        default:
            onNeedsRefresh?(false)
        }
    }
}

private let axObserverCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let pinned = Unmanaged<PinnedWindow>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        pinned.handle(notification: name)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
