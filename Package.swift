// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "boring-notch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "boringNotch", targets: ["boringNotch"]),
        .executable(name: "BoringNotchXPCHelper", targets: ["BoringNotchXPCHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/AsyncXPCConnection", exact: "1.3.0"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.5.2"),
        .package(url: "https://github.com/Lakr233/SkyLightWindow", exact: "1.0.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.6"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.4.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", exact: "1.1.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", exact: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
        .package(url: "https://github.com/TheBoredTeam/MacroVisionKit", exact: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "boringNotch",
            dependencies: [
                .product(name: "AsyncXPCConnection", package: "AsyncXPCConnection"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "Lottie", package: "lottie-spm"),
                .product(name: "MacroVisionKit", package: "MacroVisionKit"),
                .product(name: "SkyLightWindow", package: "SkyLightWindow"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ],
            path: "boringNotch",
            exclude: [
                "Info.plist",
                "Preview Content",
                "boringNotch.entitlements",
                "menu/StatusBarMenu.swift"
            ],
            resources: [
                .copy("Assets.xcassets"),
                .copy("Localizable.xcstrings"),
                .copy("boring.m4a"),
                .copy("metal")
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE"),
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreServices"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("PDFKit"),
                .linkedFramework("QuickLook"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(
            name: "BoringNotchXPCHelper",
            path: "BoringNotchXPCHelper",
            exclude: [
                "BoringNotchXPCHelper.entitlements",
                "Info.plist"
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE"),
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
