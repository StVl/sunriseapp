// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sunrise",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sunrise", targets: ["Sunrise"]),
    ],
    targets: [
        // Pure logic: alarm model, schedule, curves. No UI — covered by tests.
        .target(name: "SunriseCore"),
        .executableTarget(name: "Sunrise", dependencies: ["SunriseCore"]),
        .testTarget(name: "SunriseCoreTests", dependencies: ["SunriseCore"]),
    ]
)
