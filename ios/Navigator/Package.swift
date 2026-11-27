// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Navigator",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Navigator", targets: ["Navigator"])],
    targets: [
        .target(name: "Navigator"),
        .testTarget(name: "NavigatorTests", dependencies: ["Navigator"]),
    ]
)
