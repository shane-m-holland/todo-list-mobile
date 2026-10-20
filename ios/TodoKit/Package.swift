// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TodoKit", targets: ["TodoKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "TodoKit",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                // Generates Types.swift and Client.swift from openapi.yaml (a symlink to
                // contract/openapi.yaml) at build time. Nothing generated is committed.
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "TodoKitTests",
            dependencies: [
                "TodoKit",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
    ]
)
