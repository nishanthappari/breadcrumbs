// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Breadcrumbs",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Breadcrumbs", targets: ["Breadcrumbs"]),
        .library(name: "BreadcrumbsCore", targets: ["BreadcrumbsCore"]),
    ],
    targets: [
        .target(name: "BreadcrumbsCore"),
        .executableTarget(name: "Breadcrumbs", dependencies: ["BreadcrumbsCore"]),
        .testTarget(name: "BreadcrumbsCoreTests", dependencies: ["BreadcrumbsCore"]),
    ],
    swiftLanguageModes: [.v5]
)
