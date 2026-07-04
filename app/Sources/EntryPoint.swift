import AppKit
import Darwin

@main
enum TranslateAppMain {
    static func main() {
        setbuf(stdout, nil)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
