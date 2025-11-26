// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "TreeSitterJSON5",
    platforms: [
        .iOS(.v14), .macCatalyst(.v14),
    ],
    products: [
        .library(name: "TreeSitterJSON5", targets: ["TreeSitterJSON5"]),
        .library(name: "TreeSitterJSON5Queries", targets: ["TreeSitterJSON5Queries"]),
        .library(name: "TreeSitterJSON5Runestone", targets: ["TreeSitterJSON5Runestone"]),
    ],
    dependencies: [
        .package(path: "../Runestone"),
    ],
    targets: [
        .target(name: "TreeSitterJSON5", cSettings: [.headerSearchPath("src")]),
        .target(name: "TreeSitterJSON5Queries", resources: [.copy("highlights.scm"), .copy("injections.scm")]),
        .target(name: "TreeSitterJSON5Runestone", dependencies: ["Runestone", "TreeSitterJSON5", "TreeSitterJSON5Queries"]),
    ]
)
