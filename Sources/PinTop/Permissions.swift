import AppKit

@MainActor
enum Permissions {
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let screenRecordingSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static var hasAccessibility: Bool { AX.isTrusted }
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompts once on launch if something is missing.
    static func requestOnLaunch() {
        if !hasAccessibility {
            AX.requestTrust()
        }
        if !hasScreenRecording {
            CGRequestScreenCaptureAccess()
        }
    }

    /// Returns true when pinning can work; otherwise explains what is missing.
    static func ensureGranted() -> Bool {
        if !hasAccessibility {
            showAlert(
                title: "Accessibility Access Required",
                message: "PinTop needs Accessibility access to find, track and focus windows.\n\nEnable PinTop in System Settings › Privacy & Security › Accessibility.",
                url: accessibilitySettingsURL
            )
            return false
        }
        if !hasScreenRecording {
            showAlert(
                title: "Screen Recording Access Required",
                message: "macOS does not let apps change the stacking level of other apps' windows, so PinTop keeps a live view of the pinned window on top. This requires Screen Recording access.\n\nEnable PinTop in System Settings › Privacy & Security › Screen & System Audio Recording, then restart PinTop.",
                url: screenRecordingSettingsURL
            )
            return false
        }
        return true
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func showAlert(title: String, message: String, url: URL) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            open(url)
        }
    }
}
