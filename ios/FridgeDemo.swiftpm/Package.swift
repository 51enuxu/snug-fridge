// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "FridgeDemo",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "FridgeDemo",
            targets: ["AppModule"],
            bundleIdentifier: "io.github.snugfridge.demo",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .map),
            accentColor: .presetColor(.pink),
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [.portrait],
            capabilities: [
                .camera(purposeString: "拍照抠成食物贴纸或贴在冰箱门上"),
                .photoLibrary(purposeString: "从相册选照片贴在冰箱门上")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources",
            resources: [
                .copy("Resources/Fridge"),
                .copy("Resources/Fonts")
            ]
        )
    ]
)
