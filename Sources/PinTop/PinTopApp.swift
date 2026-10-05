import AppKit

@main
enum PinTopApp {
    @MainActor
    static func main() {
        // Only one instance should own the hot keys and overlays.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .contains(where: { $0 != NSRunningApplication.current }) {
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
