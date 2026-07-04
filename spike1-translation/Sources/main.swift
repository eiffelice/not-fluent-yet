import AppKit
import Foundation
import Darwin
import SwiftUI
import Translation

@main
enum Spike1TranslationMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = Spike1AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class Spike1AppDelegate: NSObject, NSApplicationDelegate {
    private var bridge: HiddenTranslationBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await runSpike()
        }
    }

    private func runSpike() async {
        print("SPIKE 1: Apple Translation framework headless/offscreen usage")

        guard #available(macOS 15.0, *) else {
            print("FAIL: macOS 15+ is required for the Translation framework.")
            finish(1)
            return
        }

        let args = Spike1Args.parse(CommandLine.arguments)
        let text = "สวัสดีครับ วันนี้อากาศดีมาก"
        let source = Locale.Language(identifier: args.sourceLanguage)
        let target = Locale.Language(identifier: args.targetLanguage)

        print("INFO: Source language: \(args.sourceLanguage)")
        print("INFO: Target language: \(args.targetLanguage)")
        print("INFO: Test input: \(text)")
        print("INFO: Hidden host window: \(args.debugWindow ? "debug-visible" : "offscreen/invisible")")

        do {
            let service = HiddenTranslationBridge(debugWindow: args.debugWindow)
            self.bridge = service

            let translated = try await service.translate(text: text, source: source, target: target)
            print("RESULT: \(translated)")

            let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            let containsLatin = trimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil
            if !trimmed.isEmpty && containsLatin {
                print("PASS: Translation returned a non-empty English-looking string.")
                finish(0)
            } else {
                print("FAIL: Translation completed, but the result was empty or did not look English.")
                finish(2)
            }
        } catch let error as TranslationSpikeError {
            print("FAIL: \(error.message)")
            finish(error.exitCode)
        } catch {
            print("FAIL: Translation threw an unexpected error: \(error)")
            print("INFO: If this mentions language assets, approve/download the prompted language pack and re-run.")
            finish(10)
        }
    }

    private func finish(_ code: Int32) {
        fflush(stdout)
        fflush(stderr)
        NSApp.terminate(nil)
        exit(code)
    }
}

struct Spike1Args {
    var sourceLanguage = "th"
    var targetLanguage = "en"
    var debugWindow = false

    static func parse(_ raw: [String]) -> Spike1Args {
        var args = Spike1Args()
        var iterator = raw.dropFirst().makeIterator()

        while let arg = iterator.next() {
            switch arg {
            case "--from":
                if let value = iterator.next() { args.sourceLanguage = value }
            case "--to":
                if let value = iterator.next() { args.targetLanguage = value }
            case "--debug-window":
                args.debugWindow = true
            default:
                break
            }
        }
        return args
    }
}

enum TranslationSpikeError: Error {
    case unsupportedPair(source: String, target: String)
    case timedOut
    case noWindow
    case prepareFailed(Error)
    case translateFailed(Error)

    var exitCode: Int32 {
        switch self {
        case .unsupportedPair: return 3
        case .timedOut: return 4
        case .noWindow: return 5
        case .prepareFailed: return 7
        case .translateFailed: return 8
        }
    }

    var message: String {
        switch self {
        case .unsupportedPair(let source, let target):
            return "Unsupported translation pair: \(source) -> \(target)."
        case .timedOut:
            return "Timed out waiting for TranslationSession from the hidden SwiftUI view."
        case .noWindow:
            return "Could not create the hidden/offscreen host window."
        case .prepareFailed(let error):
            return "prepareTranslation() failed: \(error). If the system shows a language download prompt, approve it and re-run."
        case .translateFailed(let error):
            return "session.translate(_:) failed: \(error)."
        }
    }
}

@available(macOS 15.0, *)
@MainActor
final class HiddenTranslationBridge {
    private var window: NSWindow?
    private let debugWindow: Bool

    init(debugWindow: Bool) {
        self.debugWindow = debugWindow
    }

    func translate(text: String, source: Locale.Language, target: Locale.Language) async throws -> String {
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)

        switch status {
        case .installed:
            print("INFO: Language pair status: installed.")
        case .supported:
            print("INFO: Language pair status: supported, but language assets may need download.")
            print("INFO: The spike will call prepareTranslation() to trigger Apple's system download prompt if needed.")
        case .unsupported:
            throw TranslationSpikeError.unsupportedPair(source: String(describing: source), target: String(describing: target))
        @unknown default:
            print("INFO: Language pair status: unknown future case; continuing to translate.")
        }

        return try await withThrowingTimeout(seconds: 120) {
            try await withCheckedThrowingContinuation { continuation in
                var didResume = false

                let complete: (Result<String, Error>) -> Void = { [weak self] result in
                    Task { @MainActor in
                        guard !didResume else { return }
                        didResume = true
                        self?.window?.orderOut(nil)
                        self?.window = nil

                        switch result {
                        case .success(let value):
                            continuation.resume(returning: value)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }

                let view = HiddenTranslationView(
                    text: text,
                    source: source,
                    target: target,
                    onComplete: complete
                )

                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(x: 0, y: 0, width: 12, height: 12)

                let rect: NSRect
                if self.debugWindow {
                    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 800, height: 600)
                    rect = NSRect(x: screen.minX + 40, y: screen.minY + 40, width: 12, height: 12)
                } else {
                    rect = NSRect(x: -30_000, y: -30_000, width: 12, height: 12)
                }

                let window = NSWindow(
                    contentRect: rect,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.alphaValue = self.debugWindow ? 0.18 : 0.01
                window.ignoresMouseEvents = true
                window.level = .floating

                self.window = window
                window.orderFrontRegardless()
            }
        }
    }
}

@available(macOS 15.0, *)
struct HiddenTranslationView: View {
    let text: String
    let source: Locale.Language
    let target: Locale.Language
    let onComplete: (Result<String, Error>) -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var started = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                guard !started else { return }
                started = true
                configuration = TranslationSession.Configuration(source: source, target: target)
            }
            .translationTask(configuration) { session in
                do {
                    print("INFO: Calling prepareTranslation()...")
                    do {
                        try await session.prepareTranslation()
                    } catch {
                        onComplete(.failure(TranslationSpikeError.prepareFailed(error)))
                        return
                    }

                    print("INFO: Calling session.translate(_:)...")
                    do {
                        let response = try await session.translate(text)
                        onComplete(.success(response.targetText))
                    } catch {
                        onComplete(.failure(TranslationSpikeError.translateFailed(error)))
                    }
                }
            }
    }
}

func withThrowingTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw TranslationSpikeError.timedOut
        }

        guard let result = try await group.next() else {
            throw TranslationSpikeError.timedOut
        }
        group.cancelAll()
        return result
    }
}
