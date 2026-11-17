// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XuanPian",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "XuanPian",
            path: "Sources/XuanPian",
            sources: ["XuanPianApp.swift", "Models.swift", "PreviewService.swift", "Store.swift", "Sheets.swift", "Design.swift"]
        ),
        .testTarget(
            name: "XuanPianTests",
            dependencies: ["XuanPian"],
            path: "Tests/XuanPianTests"
        ),
    ]
)
