import AppKit
import Carbon.HIToolbox
import Foundation
import Darwin

@main
enum Spike3PanelMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = Spike3AppDelegate(args: Spike3Args.parse(CommandLine.arguments))
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class Spike3AppDelegate: NSObject, NSApplicationDelegate {
    private let args: Spike3Args
    private var controller: PanelController?

    init(args: Spike3Args) {
        self.args = args
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("SPIKE 3: Non-activating floating input panel")
        print("INFO: Hotkey: \(args.hotkey.description)")
        print("INFO: Press the hotkey, type into the panel, then press Escape.")

        let controller = PanelController(args: args)
        self.controller = controller
        controller.start()
    }
}

struct Spike3Args {
    var hotkey = HotKey.default

    static func parse(_ raw: [String]) -> Spike3Args {
        var args = Spike3Args()
        var iterator = raw.dropFirst().makeIterator()

        while let arg = iterator.next() {
            switch arg {
            case "--hotkey":
                if let value = iterator.next(), let parsed = HotKey.parse(value) {
                    args.hotkey = parsed
                } else {
                    print("WARN: Could not parse --hotkey. Using default Ctrl+Option+T.")
                }
            default:
                break
            }
        }
        return args
    }
}

struct HotKey {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let description: String

    static let `default` = HotKey(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | optionKey),
        description: "ctrl+option+t"
    )

    static func parse(_ raw: String) -> HotKey? {
        let parts = raw.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let keyPart = parts.last, let keyCode = keyCodeForKeyName(keyPart) else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }

        guard modifiers != 0 else { return nil }
        return HotKey(keyCode: UInt32(keyCode), carbonModifiers: modifiers, description: parts.joined(separator: "+"))
    }

    private static func keyCodeForKeyName(_ key: String) -> Int? {
        let table: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "space": kVK_Space
        ]
        return table[key]
    }
}

@MainActor
final class PanelController {
    private let args: Spike3Args
    private let textField = EscapeAwareTextField(frame: .zero)
    private var panel: NonActivatingInputPanel!
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var frontmostBeforePanel: NSRunningApplication?
    private var localMonitor: Any?

    init(args: Spike3Args) {
        self.args = args
        self.textField.onEscape = { [weak self] in
            self?.hidePanelAndEvaluate()
        }
        createPanel()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func start() {
        installEscapeMonitor()
        installGlobalHotKey()
    }

    private func createPanel() {
        panel = NonActivatingInputPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 96),
            styleMask: [.nonactivatingPanel, .titled],
            backing: .buffered,
            defer: false
        )

        panel.title = "Spike 3 Input Panel"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        textField.placeholderString = "Type here, then press Escape"
        textField.font = NSFont.systemFont(ofSize: 20)
        textField.isBezeled = true
        textField.isEditable = true
        textField.isSelectable = true
        textField.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Non-activating input panel test")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 96))
        content.addSubview(label)
        content.addSubview(textField)
        panel.contentView = content

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            textField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            textField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            textField.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func installEscapeMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.hidePanelAndEvaluate()
                return nil
            }
            return event
        }
    }

    private func installGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("SPK3"), id: 1)

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<PanelController>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                controller.showPanel()
            }
            return noErr
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            print("FAIL: InstallEventHandler failed with OSStatus \(installStatus).")
            exit(1)
        }

        let registerStatus = RegisterEventHotKey(
            args.hotkey.keyCode,
            args.hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            print("FAIL: RegisterEventHotKey failed with OSStatus \(registerStatus). The hotkey may be reserved by another app.")
            exit(2)
        }

        print("INFO: Global hotkey registered. Keep another app focused, then press \(args.hotkey.description).")
    }

    private func showPanel() {
        frontmostBeforePanel = NSWorkspace.shared.frontmostApplication
        let beforeName = appName(frontmostBeforePanel)
        print("INFO: Frontmost before showing panel: \(beforeName)")

        textField.stringValue = ""
        centerPanelOnActiveScreen()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(textField)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let current = NSWorkspace.shared.frontmostApplication
            print("INFO: Frontmost while panel is visible: \(self.appName(current))")
        }
    }

    private func hidePanelAndEvaluate() {
        guard panel.isVisible else { return }

        let typedText = textField.stringValue
        panel.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let after = NSWorkspace.shared.frontmostApplication
            let afterName = self.appName(after)
            let beforeName = self.appName(self.frontmostBeforePanel)
            let focusMatches = after?.processIdentifier == self.frontmostBeforePanel?.processIdentifier
            let typed = !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            print("INFO: Frontmost after hiding panel: \(afterName)")
            print("INFO: Typed text captured by panel: \(typed ? "yes" : "no")")

            let exitCode: Int32
            if focusMatches && typed {
                print("PASS: Previous app still has focus and the non-activating panel accepted keyboard input.")
                exitCode = 0
            } else if !focusMatches && typed {
                print("FAIL: Panel accepted typing, but focus changed. Before=\(beforeName), After=\(afterName).")
                exitCode = 3
            } else if focusMatches && !typed {
                print("FAIL: Focus matched, but the text field did not capture typed input before Escape.")
                exitCode = 4
            } else {
                print("FAIL: Focus changed and no typed input was captured. Before=\(beforeName), After=\(afterName).")
                exitCode = 5
            }

            fflush(stdout)
            fflush(stderr)
            NSApp.terminate(nil)
            exit(exitCode)
        }
    }

    private func centerPanelOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            panel.center()
            return
        }

        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func appName(_ app: NSRunningApplication?) -> String {
        guard let app else { return "<none>" }
        return "\(app.localizedName ?? app.bundleIdentifier ?? "<unknown>") [pid=\(app.processIdentifier)]"
    }
}

final class NonActivatingInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class EscapeAwareTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
