import AppKit

struct WindowServerInfo {
    /// Window bounds in global coordinates with the origin at the top-left of the primary display.
    let bounds: CGRect
    /// False when the window is minimized, hidden or on another Space.
    let isOnScreen: Bool
}

enum WindowServer {
    /// Fetches live bounds for the given windows in a single call; closed windows are absent from the result.
    static func info(for windowIDs: [CGWindowID]) -> [CGWindowID: WindowServerInfo] {
        guard !windowIDs.isEmpty else { return [:] }
        var values = windowIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(kCFAllocatorDefault, &values, values.count, nil),
              let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [:] }

        var result: [CGWindowID: WindowServerInfo] = [:]
        for entry in list {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
            result[number.uint32Value] = WindowServerInfo(bounds: bounds, isOnScreen: onScreen)
        }
        return result
    }

    /// Converts a top-left-origin rect (CoreGraphics / Accessibility) to AppKit screen coordinates.
    @MainActor
    static func appKitRect(fromTopLeft rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
