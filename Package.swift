// swift-tools-version: 5.6

import PackageDescription
import Foundation

let package = Package(
    name: "PDFtoJSON",
    products: [
        .library( name: "PDFtoJSON", targets: ["PDFtoJSON"] )
    ],
    dependencies: [
        .package(url: "https://github.com/KittyMac/Hitch.git", from: "0.4.121"),
        .package(url: "https://github.com/KittyMac/Spanker.git", from: "0.2.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.5.0"),
        .package(url: "https://github.com/KittyMac/GzipSwift.git", from: "5.3.4"),
    ],
    targets: [
        .target(
            name: "PDFtoJSON",
            dependencies: [
                "Hitch",
                "Spanker",
                "CryptoSwift",
                .product(name: "Gzip", package: "GzipSwift"),
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
