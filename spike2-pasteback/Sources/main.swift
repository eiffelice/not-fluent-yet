import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Darwin

@main
enum Spike2PastebackMain {
    @MainActor
    static func main() async {
        let args = Spike2Args.parse(CommandLine.arguments)

        print("SPIKE 2: Clipboard-safe paste-back into the frontmost app")
        print("INFO: Test paste string: \(args.testString)")
        print("INFO: Capture delay: \(args.captureDelayMs) ms")
        print("INFO: Focus-to-paste delay: \(args.pasteDelayMs) ms")

        if args.captureDelayMs > 0 {
            print("INFO: Waiting before capturing frontmost app. Use this time to focus TextEdit or another target app.")
            await sleepMs(args.captureDelayMs)
        }

        guard let previousApp = NSWorkspace.shared.frontmostApplication else {
            print("FAIL: Could not read the current frontmost application.")
            exit(2)
        }

        let previousName = previousApp.localizedName ?? previousApp.bundleIdentifier ?? "<unknown>"
        print("INFO: Captured frontmost app before paste: \(previousName) [pid=\(previousApp.processIdentifier)]")

        guard accessibilityTrusted(prompt: true) else {
            print("FAIL: Accessibility permission is not granted.")
            print("ACTION: Grant permission to the host app in System Settings > Privacy & Security > Accessibility, then re-run.")
            print("NOTE: If running via Terminal, grant Accessibility to Terminal/iTerm/your shell host. If running the built binary directly, grant it to the binary/app wrapper.")
            exit(1)
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        print("INFO: Saved pasteboard items: \(snapshot.items.count), total types: \(snapshot.typeCount)")

        do {
            try writeTestString(args.testString, to: pasteboard)
            print("INFO: Wrote test string to pasteboard.")

            let activated = previousApp.activate(options: [])
            print("INFO: Requested re-activation of previous app: \(activated ? "accepted" : "not guaranteed")")

            await sleepMs(args.pasteDelayMs)

            try sendCommandV()
            print("INFO: Posted Cmd+V via CGEvent to the HID event tap.")

            await sleepMs(args.restoreDelayMs)

            snapshot.restore(to: pasteboard)
            let restoreVerified = snapshot.matchesCurrentPasteboard(pasteboard)
            print("INFO: Restored original pasteboard contents after \(args.restoreDelayMs) ms. Verified: \(restoreVerified ? "yes" : "best-effort")")

            let now = NSWorkspace.shared.frontmostApplication
            let focusMatches = now?.processIdentifier == previousApp.processIdentifier
            if focusMatches {
                print("PASS: Paste event was posted and the original pasteboard contents were restored. Manually verify \"\(args.testString)\" appeared in \(previousName).")
                exit(0)
            } else {
                let nowName = now?.localizedName ?? now?.bundleIdentifier ?? "<unknown>"
                print("FAIL: Paste event posted and pasteboard restored, but focus changed to \(nowName). This is likely a timing/focus race.")
                exit(3)
            }
        } catch {
            snapshot.restore(to: pasteboard)
            print("FAIL: \(error)")
            print("INFO: Original pasteboard was restored in the error path.")
            exit(4)
        }
    }
}

struct Spike2Args {
    var pasteDelayMs: UInt64 = 300
    var restoreDelayMs: UInt64 = 300
    var captureDelayMs: UInt64 = 0
    var testString = "HELLO_FROM_SPIKE2"

    static func parse(_ raw: [String]) -> Spike2Args {
        var args = Spike2Args()
        var iterator = raw.dropFirst().makeIterator()

        while let arg = iterator.next() {
            switch arg {
            case "--paste-delay-ms":
                if let value = iterator.next(), let parsed = UInt64(value) { args.pasteDelayMs = parsed }
            case "--restore-delay-ms":
                if let value = iterator.next(), let parsed = UInt64(value) { args.restoreDelayMs = parsed }
            case "--capture-delay-ms":
                if let value = iterator.next(), let parsed = UInt64(value) { args.captureDelayMs = parsed }
            case "--string":
                if let value = iterator.next() { args.testString = value }
            default:
                break
            }
        }
        return args
    }
}

enum PastebackError: Error, CustomStringConvertible {
    case failedToWritePasteboard
    case failedToCreateKeyEvent

    var description: String {
        switch self {
        case .failedToWritePasteboard:
            return "Could not write the test string to NSPasteboard.general."
        case .failedToCreateKeyEvent:
            return "Could not create CGEvent objects for Cmd+V."
        }
    }
}

struct PasteboardSnapshot {
    let items: [NSPasteboardItem]

    var typeCount: Int {
        items.reduce(0) { $0 + $1.types.count }
    }

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                } else if let string = original.string(forType: type) {
                    copy.setString(string, forType: type)
                }
            }
            return copy
        }
        return PasteboardSnapshot(items: copiedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            _ = pasteboard.writeObjects(items)
        }
    }

    func matchesCurrentPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let current = PasteboardSnapshot.capture(from: pasteboard)
        return current.fingerprint == fingerprint
    }

    private var fingerprint: [String] {
        items.map { item in
            item.types.map { type in
                let length = item.data(forType: type)?.count ?? item.string(forType: type)?.utf8.count ?? -1
                return "\(type.rawValue):\(length)"
            }.sorted().joined(separator: "|")
        }
    }
}

func accessibilityTrusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func writeTestString(_ value: String, to pasteboard: NSPasteboard) throws {
    pasteboard.clearContents()
    let ok = pasteboard.setString(value, forType: .string)
    if !ok { throw PastebackError.failedToWritePasteboard }
}

func sendCommandV() throws {
    // macOS virtual key code for the physical V key on ANSI keyboards.
    let keyV = CGKeyCode(0x09)
    let source = CGEventSource(stateID: .hidSystemState)

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
        throw PastebackError.failedToCreateKeyEvent
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

func sleepMs(_ milliseconds: UInt64) async {
    try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
}
