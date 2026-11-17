// swift-tools-version: 6.0
// FormatWheelCore: catalog, engine, every conversion op, privacy scan, FFmpeg runner, output handling.
// Must not import UIKit, AppKit or SwiftUI — UI-only capabilities are injected by the app (see Platform.swift).
import PackageDescription

let package = Package(
    name: "FormatWheelCore",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FormatWheelCore", type: .dynamic, targets: ["FormatWheelCore"]),
    ],
    targets: [
        // Prebuilt by scripts/build-ffmpeg.sh, downloaded by scripts/fetch-ffmpeg.sh.
        .binaryTarget(name: "FWFFmpeg", path: "Vendor/FWFFmpeg.xcframework"),
        .binaryTarget(name: "WebP", path: "Vendor/WebP.xcframework"),
        .target(
            name: "FormatWheelCore",
            dependencies: ["FWFFmpeg", "WebP"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
