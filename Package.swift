// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
let macProducts: [Product] = [
    .executable(name: "TUMMac", targets: ["TUMMac"])
]
let macTargets: [Target] = [
    .executableTarget(
        name: "TUMMac",
        dependencies: ["TUMCore"],
        path: "Sources/TUMMac",
        exclude: ["Resources"],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI")
        ]
    )
]
#else
let macProducts: [Product] = []
let macTargets: [Target] = []
#endif

let package = Package(
    name: "TokenUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TUMCore", targets: ["TUMCore"])
    ] + macProducts,
    targets: [
        .target(
            name: "TUMCore",
            path: "Sources/TUMCore",
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS, .iOS]))
            ]
        ),
        .testTarget(
            name: "TUMCoreTests",
            dependencies: ["TUMCore"],
            path: "Tests/TUMCoreTests"
        )
    ] + macTargets
)
