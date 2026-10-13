// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MidgarKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .visionOS(.v1)],
    products: [
        .library(name: "MidgarKit", targets: ["MidgarKit"])
    ],
    targets: [
        .target(
            name: "MidgarKit",
            resources: [
                .process("Resources/catalog.fallback.json"),
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/fallback-icons"),
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "MidgarKitTests",
            dependencies: ["MidgarKit"]
        )
    ]
)
