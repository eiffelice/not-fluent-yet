import Foundation

@MainActor
final class LanguagePair {
    struct Language {
        let code: String
        let name: String
    }

    static let supportedLanguages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "th", name: "Thai"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "it", name: "Italian"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "zh", name: "Chinese (Simplified)"),
        Language(code: "ru", name: "Russian"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "vi", name: "Vietnamese"),
        Language(code: "id", name: "Indonesian"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "pl", name: "Polish"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "uk", name: "Ukrainian"),
        Language(code: "ms", name: "Malay"),
    ]

    private(set) var source: String
    private(set) var target: String

    init(source: String = "th", target: String = "en") {
        self.source = source
        self.target = target
    }

    var description: String {
        "\(source.uppercased()) → \(target.uppercased())"
    }

    static func displayName(for code: String) -> String {
        supportedLanguages.first { $0.code == code }?.name ?? code.uppercased()
    }

    func swap() {
        let oldSource = source
        source = target
        target = oldSource
    }

    func setSource(_ code: String) {
        source = code
    }

    func setTarget(_ code: String) {
        target = code
    }
}
