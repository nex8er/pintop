import AppKit
import CoreMedia
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .windowNotFound: "The window is no longer available for capture."
        }
    }
}

/// Streams the live contents of a single window (even while it is covered by other windows).
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called on the main thread with every complete frame and, now and then, the window's
    /// corner radius in pixels measured from the frame's transparent corners.
    var onFrame: ((IOSurface, CGFloat?) -> Void)?
    /// Called on the main thread when the stream stops unexpectedly (e.g. the window closed).
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "PinTop.capture", qos: .userInteractive)
    private var frameCount = 0 // Accessed only on `queue`.

    func start(windowID: CGWindowID, size: CGSize, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let stream = SCStream(filter: filter, configuration: Self.configuration(size: size, scale: scale), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func update(size: CGSize, scale: CGFloat) {
        stream?.updateConfiguration(Self.configuration(size: size, scale: scale)) { _ in }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        stream.stopCapture { _ in }
    }

    private static func configuration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 4
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        return config
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        let radius = frameCount % 15 == 0 ? Self.measureCornerRadius(surface) : nil
        frameCount &+= 1
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(surface, radius)
        }
    }

    /// Windows have transparent rounded corners in the captured frame. Walking the top-left
    /// diagonal to the first mostly-opaque pixel gives the radius: the corner arc crosses
    /// the diagonal at r·(1 − 1/√2) from the corner on each axis.
    private static func measureCornerRadius(_ surface: IOSurface) -> CGFloat? {
        guard surface.lock(options: .readOnly, seed: nil) == kIOReturnSuccess else { return nil }
        defer { surface.unlock(options: .readOnly, seed: nil) }

        let base = surface.baseAddress
        let bytesPerRow = surface.bytesPerRow
        let limit = min(surface.width, surface.height, 240) / 2
        func alpha(_ i: Int) -> CGFloat {
            CGFloat(base.load(fromByteOffset: i * bytesPerRow + i * 4 + 3, as: UInt8.self)) / 255
        }

        var previous: CGFloat = 0
        for i in 0..<limit {
            let current = alpha(i)
            guard current >= 0.5 else {
                previous = current
                continue
            }
            if i == 0 { return 0 } // Square corners.
            // Sub-pixel position of the 50% crossing between the two pixel centers.
            let crossing = CGFloat(i) - 0.5 + (0.5 - previous) / max(current - previous, 0.001)
            return crossing / (1 - 1 / 2.0.squareRoot())
        }
        return nil // Transparent content (e.g. a see-through terminal): keep the previous value.
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.onStop?(error)
        }
    }
}
