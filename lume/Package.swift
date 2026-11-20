// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lume",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.5.0"),
        .package(url: "https://github.com/atacan/swift-highlight", from: "0.0.2"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Lume",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftHighlight", package: "swift-highlight"),
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        )
    ]
)
