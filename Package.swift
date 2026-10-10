// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabletopKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ArtExtraction", targets: ["ArtExtraction"]),
        .library(name: "ArtExtractionTestSupport", targets: ["ArtExtractionTestSupport"]),
        .library(name: "Bestiary", targets: ["Bestiary"])
    ],
    targets: [
        .target(name: "ArtExtraction"),
        .target(name: "ArtExtractionTestSupport", dependencies: ["ArtExtraction"]),
        .testTarget(name: "ArtExtractionTests", dependencies: ["ArtExtraction", "ArtExtractionTestSupport"]),
        .target(name: "Bestiary"),
        .testTarget(name: "BestiaryTests", dependencies: ["Bestiary"])
    ]
)
