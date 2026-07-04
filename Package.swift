// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacTranslateSpikes",
    platforms: [
        // String form keeps this manifest compatible with SwiftPM 5.9 while targeting macOS 15+ SDKs.
        .macOS("15.0")
    ],
    products: [
        .executable(name: "spike1-translation", targets: ["Spike1Translation"]),
        .executable(name: "spike2-pasteback", targets: ["Spike2Pasteback"]),
        .executable(name: "spike3-panel", targets: ["Spike3Panel"]),
        .executable(name: "translate-app", targets: ["TranslateApp"]),
        // Exposed so the Mac App Store Xcode target (AppStore/) can depend on this package
        // and reuse the exact same app logic via TranslateCoreApp.run().
        .library(name: "TranslateCore", targets: ["TranslateCore"]),
    ],
    targets: [
        .executableTarget(
            name: "Spike1Translation",
            path: "spike1-translation/Sources"
        ),
        .executableTarget(
            name: "Spike2Pasteback",
            path: "spike2-pasteback/Sources"
        ),
        .executableTarget(
            name: "Spike3Panel",
            path: "spike3-panel/Sources"
        ),
        .target(
            name: "TranslateCore",
            path: "app/Sources/TranslateCore"
        ),
        .executableTarget(
            name: "TranslateApp",
            dependencies: ["TranslateCore"],
            path: "app/Sources/TranslateApp"
        ),
    ]
)
