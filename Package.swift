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
        .package(url: "https://github.com/KittyMac/Spanker.git", from: "0.2.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.5"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PDFtoJSON",
            dependencies: [
                "Hitch",
                "Spanker",
                "SWCompression",
                "CryptoSwift"
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
