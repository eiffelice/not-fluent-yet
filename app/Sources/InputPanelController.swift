import AppKit

@available(macOS 15.0, *)
@MainActor
final class InputPanelController: NSObject, NSTextViewDelegate {
    private enum Stage {
        case input
        case listening
        case busy(hint: String)
        case confirm(translated: String)
        case copied
        case error(message: String)
    }

    private let languagePair: LanguagePair
    private let translationService = TranslationService()
    private let speechService = SpeechInputService()

    private var panel: NonActivatingInputPanel!
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let placeholderLabel = PassthroughLabel(labelWithString: "Type text to translate…")
    private let langPairLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let micButton = NSButton(frame: .zero)

    private let primaryHintLabel = NSTextField(labelWithString: "")
    private let secondaryHintLabel = NSTextField(labelWithString: "")
    private var primaryHintPill: NSView!
    private var secondaryHintPill: NSView!
    private var hintStack: NSStackView!

    private var stage: Stage = .input
    private var requestID = 0

    // Fixed and clamped in createPanel() — the text area scrolls internally instead of the
    // window growing, so this size is a hard, permanent ceiling regardless of content length.
    private static let panelSize = NSSize(width: 560, height: 176)

    init(languagePair: LanguagePair) {
        self.languagePair = languagePair
        super.init()
        textView.delegate = self
        createPanel()
    }

    // NSTextView (unlike NSTextField, which hands events to a shared field editor) receives
    // these directly, so this delegate hook reliably intercepts Return/Escape.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            handleSubmit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        updatePlaceholderVisibility()
    }

    func show() {
        if panel.isVisible {
            panel.makeKey()
            panel.makeFirstResponder(textView)
            return
        }

        requestID += 1
        print("INFO: Hotkey pressed.")

        stage = .input
        textView.string = ""
        render()

        centerPanelOnActiveScreen()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(textView)
    }

    private func handleSubmit() {
        switch stage {
        case .input:
            let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            beginTranslation(text: text)
        case .listening:
            stopListeningAndTranslate()
        case .confirm(let translated):
            copyToClipboard(text: translated)
        case .copied:
            hidePanel()
        case .busy, .error:
            break
        }
    }

    @objc private func toggleMic() {
        switch stage {
        case .input:
            startListening()
        case .listening:
            stopListeningAndTranslate()
        default:
            break
        }
    }

    private func startListening() {
        let localeID = SpeechInputService.localeIdentifier(forLanguageCode: languagePair.source)
        stage = .listening
        textView.string = ""
        render()

        let thisRequestID = requestID
        Task {
            let authorized = await SpeechInputService.requestAuthorization()
            guard thisRequestID == self.requestID else { return }
            guard authorized else {
                print("FAIL: Microphone or Speech Recognition permission not granted.")
                self.stage = .error(message: "Microphone/Speech Recognition access not granted. Grant both in System Settings > Privacy & Security.")
                self.render()
                return
            }

            do {
                try self.speechService.startListening(
                    localeIdentifier: localeID,
                    onPartialResult: { [weak self] text in
                        guard let self, thisRequestID == self.requestID else { return }
                        self.textView.string = text
                        self.updatePlaceholderVisibility()
                    },
                    onFinalResult: { [weak self] text in
                        guard let self, thisRequestID == self.requestID else { return }
                        self.finishListening(text: text)
                    },
                    onError: { [weak self] error in
                        guard let self, thisRequestID == self.requestID else { return }
                        print("FAIL: Speech recognition error: \(error)")
                        self.stage = .error(message: "Speech recognition failed: \(error)")
                        self.render()
                    }
                )
                print("INFO: Listening for speech (\(localeID))...")
            } catch {
                guard thisRequestID == self.requestID else { return }
                print("FAIL: Could not start listening: \(error)")
                self.stage = .error(message: "\(error)")
                self.render()
            }
        }
    }

    private func stopListeningAndTranslate() {
        stage = .busy(hint: "Finishing…")
        render()
        speechService.stopListening()
    }

    private func finishListening(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("INFO: No speech captured.")
            stage = .input
            render()
            return
        }
        beginTranslation(text: trimmed)
    }

    private func beginTranslation(text: String) {
        stage = .busy(hint: "Translating…")
        render()
        print("INFO: Translating \(languagePair.description): \(text)")

        let thisRequestID = requestID
        Task {
            do {
                let result = try await translationService.translate(
                    text: text,
                    source: languagePair.source,
                    target: languagePair.target
                )
                guard thisRequestID == self.requestID else {
                    print("INFO: Translation result dropped (superseded by a newer request).")
                    return
                }
                print("INFO: Translation result: \(result)")
                self.stage = .confirm(translated: result)
                self.render()
            } catch {
                guard thisRequestID == self.requestID else { return }
                print("FAIL: Translation failed: \(error)")
                self.stage = .error(message: "\(error)")
                self.render()
            }
        }
    }

    private func copyToClipboard(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print("INFO: Copied translated text to clipboard.")

        stage = .copied
        render()

        let thisRequestID = requestID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, thisRequestID == self.requestID else { return }
            self.hidePanel()
        }
    }

    private func cancel() {
        requestID += 1
        hidePanel()
    }

    private func hidePanel() {
        speechService.cancelListening()
        panel.orderOut(nil)
        stage = .input
    }

    /// Applies `stage` to every piece of chrome (text, color, spinner, hints, mic button) in one
    /// place so the panel never shows a combination of stale and fresh UI state.
    private func render() {
        langPairLabel.stringValue = languagePair.description

        switch stage {
        case .input:
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            textView.isEditable = true
            textView.textColor = .labelColor
            setHints(primary: "⏎ Translate", secondary: "⎋ Cancel", statusText: nil)
            setMic(hidden: false, listening: false)
        case .listening:
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            textView.isEditable = false
            textView.textColor = .systemRed
            setHints(primary: "⏎ Stop & Translate", secondary: "⎋ Cancel", statusText: nil)
            setMic(hidden: false, listening: true)
        case .busy(let hint):
            spinner.isHidden = false
            spinner.startAnimation(nil)
            textView.isEditable = false
            textView.textColor = .secondaryLabelColor
            setHints(primary: nil, secondary: nil, statusText: hint)
            setMic(hidden: true, listening: false)
        case .confirm(let translated):
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            textView.isEditable = false
            textView.textColor = .controlAccentColor
            textView.string = translated
            setHints(primary: "⏎ Copy", secondary: "⎋ Cancel", statusText: nil)
            setMic(hidden: true, listening: false)
        case .copied:
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            textView.isEditable = false
            textView.textColor = .controlAccentColor
            setHints(primary: nil, secondary: nil, statusText: "Copied ✓ — press ⌘V to paste")
            setMic(hidden: true, listening: false)
        case .error(let message):
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            textView.isEditable = false
            textView.textColor = .systemRed
            textView.string = message
            setHints(primary: nil, secondary: "⎋ Dismiss", statusText: nil)
            setMic(hidden: true, listening: false)
        }

        updatePlaceholderVisibility()
    }

    private func updatePlaceholderVisibility() {
        guard case .input = stage else {
            placeholderLabel.isHidden = true
            return
        }
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    private func setMic(hidden: Bool, listening: Bool) {
        micButton.isHidden = hidden
        let symbolName = listening ? "mic.fill" : "mic"
        micButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: listening ? "Stop listening" : "Start listening")
        micButton.contentTintColor = listening ? .systemRed : .secondaryLabelColor
    }

    /// Shows either the plain status text (while busy, no shortcuts apply) or the keycap-style
    /// hint pills for whichever actions are currently available. `NSStackView` collapses hidden
    /// arranged subviews automatically, so hiding one pill removes its space too.
    private func setHints(primary: String?, secondary: String?, statusText: String?) {
        if let statusText {
            statusLabel.stringValue = statusText
            statusLabel.isHidden = false
            hintStack.isHidden = true
            return
        }

        statusLabel.isHidden = true
        hintStack.isHidden = false

        primaryHintLabel.stringValue = primary ?? ""
        primaryHintPill.isHidden = (primary == nil)

        secondaryHintLabel.stringValue = secondary ?? ""
        secondaryHintPill.isHidden = (secondary == nil)
    }

    private func createPanel() {
        panel = NonActivatingInputPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Hard ceiling: whatever happens inside (long text, many lines, layout quirks), the
        // window itself can never grow or shrink past this exact size.
        panel.minSize = Self.panelSize
        panel.maxSize = Self.panelSize

        // `contentContainer` is the real contentView and owns the rounded-corner clipping.
        // `background` is a separate, lower-opacity decorative layer inside it — every other
        // control is added as a *sibling* of `background`, not a child, so lowering the blur's
        // alpha for a more see-through look doesn't dim the text sitting on top of it.
        let contentContainer = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        contentContainer.wantsLayer = true
        contentContainer.layer?.cornerRadius = 16
        contentContainer.layer?.masksToBounds = true
        contentContainer.layer?.borderWidth = 0.5
        contentContainer.layer?.borderColor = NSColor.separatorColor.cgColor

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.alphaValue = 0.8
        background.translatesAutoresizingMaskIntoConstraints = false

        langPairLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        langPairLabel.textColor = .secondaryLabelColor
        langPairLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        // NSTextView inside NSScrollView: content scrolls internally past a fixed frame instead
        // of ever demanding more space from the window — this is what actually fixes the panel
        // growing without bound for long translations or long speech transcripts.
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 19, weight: .regular)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        micButton.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Start listening")
        micButton.isBordered = false
        micButton.imageScaling = .scaleProportionallyUpOrDown
        micButton.contentTintColor = .secondaryLabelColor
        micButton.target = self
        micButton.action = #selector(toggleMic)
        micButton.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        primaryHintPill = makeHintPill(label: primaryHintLabel)
        secondaryHintPill = makeHintPill(label: secondaryHintLabel)

        let hintStack = NSStackView(views: [secondaryHintPill, primaryHintPill])
        hintStack.orientation = .horizontal
        hintStack.spacing = 6
        hintStack.alignment = .centerY
        hintStack.translatesAutoresizingMaskIntoConstraints = false
        self.hintStack = hintStack

        panel.contentView = contentContainer
        contentContainer.addSubview(background)
        contentContainer.addSubview(langPairLabel)
        contentContainer.addSubview(spinner)
        contentContainer.addSubview(scrollView)
        contentContainer.addSubview(placeholderLabel)
        contentContainer.addSubview(micButton)
        contentContainer.addSubview(divider)
        contentContainer.addSubview(statusLabel)
        contentContainer.addSubview(hintStack)

        // NSWindow automatically pins a non-autoresizing-mask content view to its own edges,
        // so `contentContainer` (the contentView itself) needs no explicit frame constraints here.
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            langPairLabel.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            langPairLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),

            spinner.centerYAnchor.constraint(equalTo: langPairLabel.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            scrollView.topAnchor.constraint(equalTo: langPairLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -10),
            scrollView.heightAnchor.constraint(equalToConstant: 72),

            placeholderLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 2),
            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 2),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor),

            micButton.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            micButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            micButton.widthAnchor.constraint(equalToConstant: 24),
            micButton.heightAnchor.constraint(equalToConstant: 24),

            divider.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: background.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),

            hintStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            hintStack.leadingAnchor.constraint(greaterThanOrEqualTo: background.leadingAnchor, constant: 20),
            hintStack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20)
        ])
    }

    private func makeHintPill(label: NSTextField) -> NSView {
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.14).cgColor
        pill.layer?.cornerRadius = 6
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7)
        ])

        return pill
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
            y: frame.midY - size.height / 2 + frame.height * 0.15
        )
        panel.setFrameOrigin(origin)
    }
}

private final class NonActivatingInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A purely visual label that never intercepts mouse events, so it can sit on top of the text
/// view as a placeholder without blocking clicks meant to focus the text view underneath it.
private final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
