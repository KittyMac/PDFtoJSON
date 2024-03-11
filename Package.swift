// swift-tools-version: 5.6

import PackageDescription
import Foundation

let package = Package(
    name: "PDFtoJSON",
    platforms: [
        .macOS(.v10_13), .iOS(.v11)
    ],
    products: [
        .library( name: "PDFtoJSON", targets: ["PDFtoJSON"] )
    ],
    dependencies: [
        .package(url: "https://github.com/KittyMac/Hitch.git", from: "0.4.121"),
        .package(url: "https://github.com/KittyMac/Spanker.git", from: "0.2.0")
    ],
    targets: [
        .target(
            name: "PDFtoJSON",
            dependencies: [
                "Hitch",
                "Spanker",
            ]
        ),
        .testTarget(
            name: "PDFtoJSONTests",
            dependencies: [
                "PDFtoJSON"
            ]
        )
    ]
)
