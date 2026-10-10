// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabletopKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ArtExtraction", targets: ["ArtExtraction"]),
        .library(name: "ArtExtractionTestSupport", targets: ["ArtExtractionTestSupport"]),
        .library(name: "Bestiary", targets: ["Bestiary"]),
        .library(name: "CreatureImport", targets: ["CreatureImport"]),
        .library(name: "BattleCards", targets: ["BattleCards"])
    ],
    targets: [
        .target(name: "ArtExtraction"),
        .target(name: "ArtExtractionTestSupport", dependencies: ["ArtExtraction"]),
        .testTarget(name: "ArtExtractionTests", dependencies: ["ArtExtraction", "ArtExtractionTestSupport"]),
        .target(name: "Bestiary"),
        .testTarget(name: "BestiaryTests", dependencies: ["Bestiary"]),
        .target(name: "CreatureImport", dependencies: ["Bestiary"]),
        .testTarget(name: "CreatureImportTests", dependencies: ["CreatureImport"], resources: [.copy("Fixtures")]),
        .target(name: "BattleCards", dependencies: ["Bestiary"])
    ]
)
