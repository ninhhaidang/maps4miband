// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BandLink",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BandLink", targets: ["BandLink"])],
    targets: [
        .target(name: "BandLink"),
        .testTarget(name: "BandLinkTests", dependencies: ["BandLink"], exclude: ["make_vectors.py"]),
    ]
)
