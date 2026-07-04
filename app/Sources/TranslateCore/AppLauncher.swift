import AppKit
import Darwin

/// The one public entry point into `TranslateCore`. Both the personal SwiftPM build
/// (`TranslateApp`) and the Mac App Store Xcode target call this — everything else in this
/// library stays internal, so there's exactly one place the two builds can diverge from.
public enum TranslateCoreApp {
    @MainActor
    public static func run() {
        setbuf(stdout, nil)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
