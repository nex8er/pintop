// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PinTop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PinTop",
            path: "Sources/PinTop",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
