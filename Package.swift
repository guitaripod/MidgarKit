// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MidgarKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .visionOS(.v1)],
    products: [
        .library(name: "MidgarKit", targets: ["MidgarKit"]),
        .library(name: "MidgarCore", targets: ["MidgarCore"]),
        .library(name: "MidgarCommerce", targets: ["MidgarCommerce"]),
        .library(name: "MidgarAccount", targets: ["MidgarAccount"]),
        .library(name: "MidgarUI", targets: ["MidgarUI"]),
        .library(name: "MidgarPortal", targets: ["MidgarPortal"]),
        .library(name: "MidgarIntelligence", targets: ["MidgarIntelligence"]),
        .library(name: "MidgarDemo", targets: ["MidgarDemo"])
    ],
    targets: [
        .target(
            name: "MidgarCore",
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(name: "MidgarCommerce", dependencies: ["MidgarCore"], exclude: ["README.md"]),
        .target(name: "MidgarAccount", dependencies: ["MidgarCore"]),
        .target(
            name: "MidgarUI",
            dependencies: ["MidgarCore"],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "MidgarPortal",
            dependencies: ["MidgarCore", "MidgarUI"],
            resources: [
                .process("Resources/catalog.fallback.json"),
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/fallback-icons"),
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "MidgarIntelligence",
            dependencies: ["MidgarCore"],
            exclude: ["README.md"],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(name: "MidgarDemo", dependencies: ["MidgarCore"], exclude: ["README.md"]),
        .target(
            name: "MidgarKit",
            dependencies: [
                "MidgarCore",
                "MidgarCommerce",
                "MidgarAccount",
                "MidgarUI",
                "MidgarPortal",
                "MidgarIntelligence",
                "MidgarDemo"
            ]
        ),
        .testTarget(name: "MidgarCoreTests", dependencies: ["MidgarCore"]),
        .testTarget(
            name: "MidgarCommerceTests",
            dependencies: ["MidgarCommerce", "MidgarCore"],
            exclude: ["StoreKitIntegrationTests.swift", "Products.storekit"]
        ),
        .testTarget(name: "MidgarAccountTests", dependencies: ["MidgarAccount"]),
        .testTarget(name: "MidgarUITests", dependencies: ["MidgarUI"]),
        .testTarget(name: "MidgarPortalTests", dependencies: ["MidgarPortal", "MidgarCore"]),
        .testTarget(name: "MidgarIntelligenceTests", dependencies: ["MidgarIntelligence"]),
        .testTarget(name: "MidgarDemoTests", dependencies: ["MidgarDemo"]),
        .testTarget(name: "MidgarKitTests", dependencies: ["MidgarKit"])
    ],
    swiftLanguageModes: [.v6]
)
