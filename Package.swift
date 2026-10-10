// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabletopKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ArtExtraction", targets: ["ArtExtraction"])
    ],
    targets: [
        .target(name: "ArtExtraction")
    ]
)
