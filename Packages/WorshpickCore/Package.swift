// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorshpickCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorshpickCore", targets: ["WorshpickCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "WorshpickCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Resources/sample-catalog.json")]
        ),
        .testTarget(
            name: "WorshpickCoreTests",
            dependencies: ["WorshpickCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
