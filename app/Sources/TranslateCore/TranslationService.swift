import AppKit
import SwiftUI
import Translation

enum TranslationServiceError: Error, CustomStringConvertible {
    case unsupportedPair(source: String, target: String)
    case timedOut
    case prepareFailed(Error)
    case translateFailed(Error)

    var description: String {
        switch self {
        case .unsupportedPair(let source, let target):
            return "Unsupported translation pair: \(source) -> \(target)."
        case .timedOut:
            return "Timed out waiting for the translation session."
        case .prepareFailed(let error):
            return "Language assets are not ready: \(error)."
        case .translateFailed(let error):
            return "Translation failed: \(error)."
        }
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationService {
    private var window: NSWindow?

    func translate(text: String, source: String, target: String) async throws -> String {
        let sourceLang = Locale.Language(identifier: source)
        let targetLang = Locale.Language(identifier: target)

        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLang, to: targetLang)

        switch status {
        case .installed:
            print("INFO: Language pair status: installed.")
        case .supported:
            print("INFO: Language pair status: supported, may need to download assets.")
        case .unsupported:
            throw TranslationServiceError.unsupportedPair(source: source, target: target)
        @unknown default:
            print("INFO: Language pair status: unknown future case; continuing.")
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
                    source: sourceLang,
                    target: targetLang,
                    onComplete: complete
                )

                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(x: 0, y: 0, width: 12, height: 12)

                let window = NSWindow(
                    contentRect: NSRect(x: -30_000, y: -30_000, width: 12, height: 12),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.alphaValue = 0.01
                window.ignoresMouseEvents = true
                window.level = .floating

                self.window = window
                window.orderFrontRegardless()
            }
        }
    }
}

@available(macOS 15.0, *)
private struct HiddenTranslationView: View {
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
                print("INFO: Calling prepareTranslation()...")
                do {
                    try await session.prepareTranslation()
                } catch {
                    onComplete(.failure(TranslationServiceError.prepareFailed(error)))
                    return
                }

                print("INFO: Calling session.translate(_:)...")
                do {
                    let response = try await session.translate(text)
                    onComplete(.success(response.targetText))
                } catch {
                    onComplete(.failure(TranslationServiceError.translateFailed(error)))
                }
            }
    }
}

private func withThrowingTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw TranslationServiceError.timedOut
        }

        guard let result = try await group.next() else {
            throw TranslationServiceError.timedOut
        }
        group.cancelAll()
        return result
    }
}
