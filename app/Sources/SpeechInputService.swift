import AVFoundation
import Speech

enum SpeechInputError: Error, CustomStringConvertible {
    case recognizerUnavailable
    case audioEngineFailure(Error)

    var description: String {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available for this language on this Mac right now."
        case .audioEngineFailure(let error):
            return "Microphone capture failed: \(error)."
        }
    }
}

@MainActor
final class SpeechInputService {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isListening = false

    /// Maps our two-letter language codes to the BCP-47 locale identifiers SFSpeechRecognizer expects.
    /// Covers every code in `LanguagePair.supportedLanguages`.
    static func localeIdentifier(forLanguageCode code: String) -> String {
        switch code {
        case "th": return "th-TH"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "zh": return "zh-CN"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "es": return "es-ES"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "ru": return "ru-RU"
        case "ar": return "ar-SA"
        case "hi": return "hi-IN"
        case "vi": return "vi-VN"
        case "id": return "id-ID"
        case "nl": return "nl-NL"
        case "pl": return "pl-PL"
        case "tr": return "tr-TR"
        case "uk": return "uk-UA"
        case "ms": return "ms-MY"
        default: return code
        }
    }

    /// Requests both Speech Recognition and Microphone access. Safe to call every time before
    /// listening starts — after the first grant, the system prompts return immediately.
    static func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startListening(
        localeIdentifier: String,
        onPartialResult: @escaping (String) -> Void,
        onFinalResult: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard !isListening else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw SpeechInputError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.request = nil
            throw SpeechInputError.audioEngineFailure(error)
        }

        isListening = true

        // SFSpeechRecognizer does not guarantee this handler runs on the main thread, but it
        // drives AppKit UI updates through the caller's closures, so every call is hopped onto
        // the main actor before touching anything.
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { @MainActor in
                    if isFinal {
                        self?.teardown()
                        onFinalResult(text)
                    } else {
                        onPartialResult(text)
                    }
                }
            }
            if let error {
                Task { @MainActor in
                    self?.teardown()
                    onError(error)
                }
            }
        }
    }

    /// Signals the end of speech so the recognizer finalizes and delivers one last result via
    /// the `onFinalResult` callback passed to `startListening`. Cleanup happens once that final
    /// result (or an error) actually arrives — see `teardown()` — not synchronously here.
    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    /// Hard-stops immediately and discards any in-flight result, e.g. when the user cancels.
    func cancelListening() {
        guard isListening else { return }
        task?.cancel()
        teardown()
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task = nil
        request = nil
        isListening = false
    }
}
