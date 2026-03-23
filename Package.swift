// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "aTerm",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "aTerm", targets: ["aTerm"]),
    ],
    targets: [
        .executableTarget(
            name: "aTerm",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "aTermTests",
            dependencies: ["aTerm"]
        ),
    ]
)
