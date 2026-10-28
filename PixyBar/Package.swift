// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixyBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PixyBar",
            path: "Sources/PixyBar",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("AVFoundation"), .linkedFramework("ServiceManagement")]
        )
    ]
)
