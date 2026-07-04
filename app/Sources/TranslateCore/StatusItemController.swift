import AppKit
import AVFoundation
import Speech
import ServiceManagement

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let languagePair: LanguagePair
    private let onQuit: () -> Void
    private var swapMenuItem: NSMenuItem?
    private var microphoneStatusItem: NSMenuItem?
    private var speechStatusItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var sourceLanguageItems: [NSMenuItem] = []
    private var targetLanguageItems: [NSMenuItem] = []

    init(languagePair: LanguagePair, onQuit: @escaping () -> Void) {
        self.languagePair = languagePair
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Type to Translate")
        }

        let menu = NSMenu()
        menu.delegate = self

        let hotkeyItem = NSMenuItem(title: "Press \(HotKey.default.description) to translate", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(.separator())

        let swapItem = NSMenuItem(title: "", action: #selector(swapDirection), keyEquivalent: "")
        swapItem.target = self
        menu.addItem(swapItem)
        self.swapMenuItem = swapItem

        let sourceItem = NSMenuItem(title: "Translate from", action: nil, keyEquivalent: "")
        let sourceSubmenu = NSMenu()
        for language in LanguagePair.supportedLanguages {
            let item = NSMenuItem(title: language.name, action: #selector(selectSourceLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.code
            sourceSubmenu.addItem(item)
            sourceLanguageItems.append(item)
        }
        sourceItem.submenu = sourceSubmenu
        menu.addItem(sourceItem)

        let targetItem = NSMenuItem(title: "Translate to", action: nil, keyEquivalent: "")
        let targetSubmenu = NSMenu()
        for language in LanguagePair.supportedLanguages {
            let item = NSMenuItem(title: language.name, action: #selector(selectTargetLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.code
            targetSubmenu.addItem(item)
            targetLanguageItems.append(item)
        }
        targetItem.submenu = targetSubmenu
        menu.addItem(targetItem)

        menu.addItem(.separator())

        let microphoneStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        microphoneStatusItem.isEnabled = false
        menu.addItem(microphoneStatusItem)
        self.microphoneStatusItem = microphoneStatusItem

        let speechStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        speechStatusItem.isEnabled = false
        menu.addItem(speechStatusItem)
        self.speechStatusItem = speechStatusItem

        let openMicrophoneItem = NSMenuItem(
            title: "Open Microphone Settings…",
            action: #selector(openMicrophoneSettings),
            keyEquivalent: ""
        )
        openMicrophoneItem.target = self
        menu.addItem(openMicrophoneItem)

        let openSpeechItem = NSMenuItem(
            title: "Open Speech Recognition Settings…",
            action: #selector(openSpeechSettings),
            keyEquivalent: ""
        )
        openSpeechItem.target = self
        menu.addItem(openSpeechItem)

        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginItem = launchAtLoginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateSwapTitle()
        updatePermissionStatuses()
        updateLaunchAtLoginState()
        updateLanguageCheckmarks()
    }

    // Refresh dynamic items (swap label, permission statuses, language checkmarks) each time the
    // menu opens, since the user may have granted permissions or changed languages elsewhere.
    func menuWillOpen(_ menu: NSMenu) {
        updateSwapTitle()
        updatePermissionStatuses()
        updateLaunchAtLoginState()
        updateLanguageCheckmarks()
    }

    private func updateSwapTitle() {
        swapMenuItem?.title = "Swap direction (currently \(languagePair.description))"
    }

    private func updateLanguageCheckmarks() {
        for item in sourceLanguageItems {
            item.state = (item.representedObject as? String) == languagePair.source ? .on : .off
        }
        for item in targetLanguageItems {
            item.state = (item.representedObject as? String) == languagePair.target ? .on : .off
        }
    }

    private func updatePermissionStatuses() {
        let microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        microphoneStatusItem?.title = microphoneGranted ? "Microphone: Granted ✓" : "Microphone: Not granted ⚠️"

        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        speechStatusItem?.title = speechGranted ? "Speech Recognition: Granted ✓" : "Speech Recognition: Not granted ⚠️"
    }

    private func updateLaunchAtLoginState() {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func swapDirection() {
        languagePair.swap()
        updateSwapTitle()
        updateLanguageCheckmarks()
    }

    @objc private func selectSourceLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        languagePair.setSource(code)
        updateSwapTitle()
        updateLanguageCheckmarks()
    }

    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        languagePair.setTarget(code)
        updateSwapTitle()
        updateLanguageCheckmarks()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("FAIL: Could not update Launch at Login: \(error)")
        }
        updateLaunchAtLoginState()
    }

    @objc private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSpeechSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        onQuit()
    }
}
