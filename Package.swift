// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Faccy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Faccy", targets: ["Faccy"])
    ],
    targets: [
        .executableTarget(
            name: "Faccy",
            path: "Sources/Faccy"
        )
    ],
    swiftLanguageModes: [.v5]
)
