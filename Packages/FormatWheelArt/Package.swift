// swift-tools-version: 6.0
// FormatWheelArt: format glyphs, weapon silhouettes, drawing helpers, theme and synthesized SFX.
// Pure CoreGraphics / CoreText / AVAudioEngine — shared by the app, snapshot tests and the icon script.
import PackageDescription

let package = Package(
    name: "FormatWheelArt",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FormatWheelArt", type: .dynamic, targets: ["FormatWheelArt"]),
    ],
    targets: [
        .target(name: "FormatWheelArt", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FormatWheelArtTests", dependencies: ["FormatWheelArt"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
