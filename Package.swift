// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DittoMac",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "DittoMac",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
