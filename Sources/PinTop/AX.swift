import AppKit
import ApplicationServices

/// Private but long-stable API that maps an AX window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    static func title(of window: AXUIElement) -> String? {
        value(window, kAXTitleAttribute) as? String
    }

    /// Brings the window's app to the front and raises the window above the app's other windows.
    static func focus(window: AXUIElement, app: AXUIElement, pid: pid_t) {
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}

/// The focused window of the frontmost application – the one the user means by "active window".
struct WindowTarget {
    let pid: pid_t
    let app: AXUIElement
    let window: AXUIElement
    let windowID: CGWindowID
    let appName: String

    @MainActor
    static func frontmost() -> WindowTarget? {
        guard AX.isTrusted,
              let running = NSWorkspace.shared.frontmostApplication,
              running.processIdentifier != getpid() else { return nil }
        let pid = running.processIdentifier
        let app = AX.application(pid: pid)
        guard let window = AX.focusedWindow(of: app), let windowID = AX.windowID(of: window) else { return nil }
        return WindowTarget(pid: pid, app: app, window: window, windowID: windowID,
                            appName: running.localizedName ?? "Window")
    }
}
