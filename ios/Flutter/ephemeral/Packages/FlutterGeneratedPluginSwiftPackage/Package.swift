// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "url_launcher_ios", path: "../.packages/url_launcher_ios-6.4.1"),
        .package(name: "permission_handler_apple", path: "../.packages/permission_handler_apple-9.4.9"),
        .package(name: "package_info_plus", path: "../.packages/package_info_plus-9.0.1"),
        .package(name: "geolocator_apple", path: "../.packages/geolocator_apple-2.3.13"),
        .package(name: "reactive_ble_mobile", path: "../.packages/reactive_ble_mobile-5.5.0"),
        .package(name: "flutter_blue_plus_darwin", path: "../.packages/flutter_blue_plus_darwin-7.0.3"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "url-launcher-ios", package: "url_launcher_ios"),
                .product(name: "permission-handler-apple", package: "permission_handler_apple"),
                .product(name: "package-info-plus", package: "package_info_plus"),
                .product(name: "geolocator-apple", package: "geolocator_apple"),
                .product(name: "reactive-ble-mobile", package: "reactive_ble_mobile"),
                .product(name: "flutter-blue-plus-darwin", package: "flutter_blue_plus_darwin"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
