// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopyClipOSS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CopyClipOSS",
            path: "Sources/CopyClipOSS",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ],
    swiftLanguageVersions: [.v5]
)
