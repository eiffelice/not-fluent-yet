import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let languagePair = LanguagePair()
    private var statusItemController: StatusItemController?
    private var hotKeyManager: HotKeyManager?

    @available(macOS 15.0, *)
    private var panelController: InputPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard #available(macOS 15.0, *) else {
            let alert = NSAlert()
            alert.messageText = "macOS 15 or newer is required."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let panelController = InputPanelController(languagePair: languagePair)
        self.panelController = panelController

        statusItemController = StatusItemController(
            languagePair: languagePair,
            onQuit: { NSApp.terminate(nil) }
        )

        let hotKeyManager = HotKeyManager(hotkey: .default) { [weak panelController] in
            panelController?.show()
        }
        self.hotKeyManager = hotKeyManager
        hotKeyManager.register()

        print("Type-to-Translate is running in the menu bar. Press \(HotKey.default.description) to translate.")
    }
}
