# macOS Type-to-Translate Technical Spikes

Proof-of-concept Swift project for validating three technical risks before building a full macOS menu bar "type-to-translate" app.

It contains three separate minimal spike executables that were used to validate each risk in isolation, plus a minimal real app (`app/`, product name `translate-app`) that wires the three validated approaches together into one long-running menu bar app.

- `spike1-translation/` — Apple Translation framework headless/offscreen usage.
- `spike2-pasteback/` — clipboard-safe paste-back into the previous app with `CGEvent` Cmd+V.
- `spike3-panel/` — non-activating floating input panel with global hotkey.
- `app/` — the real menu bar app combining all three.

## Requirements

- macOS 15+ Sequoia.
- Xcode 16+ recommended because the Apple `Translation` framework is a macOS 15 SDK API.
- Swift 5.9+.
- App Sandbox must be disabled for the real product direction that uses global events, Accessibility, paste-back, and nonstandard app focus behavior.
- No third-party dependencies.

The Swift Package command-line executables are unsandboxed by default. If you convert these spikes into app targets in Xcode, do **not** enable App Sandbox. This means this architecture is not suitable for Mac App Store distribution without redesigning the paste-back/global-event approach.

## Build

```bash
cd mac-translate-spikes
swift build
```

Build one spike:

```bash
swift build --product spike1-translation
swift build --product spike2-pasteback
swift build --product spike3-panel
```

You can also open the folder in Xcode as a Swift Package.

## Spike 1 — Apple Translation framework, headless/offscreen usage

Goal: prove that code outside a visible translation UI can call translation through a hidden SwiftUI host view that owns `.translationTask`.

Run:

```bash
swift run spike1-translation
```

Optional arguments:

```bash
swift run spike1-translation --from th --to en
swift run spike1-translation --debug-window
```

Expected output shape:

```text
SPIKE 1: Apple Translation framework headless/offscreen usage
INFO: Source language: th
INFO: Target language: en
INFO: Test input: สวัสดีครับ วันนี้อากาศดีมาก
INFO: Language pair status: installed.
INFO: Calling prepareTranslation()...
INFO: Calling session.translate(_:)...
RESULT: Hello, today the weather is very nice.
PASS: Translation returned a non-empty English-looking string.
```

Known failure modes:

- `FAIL: macOS 15+ is required...` — run on macOS 15 or newer.
- `Unsupported translation pair` — the source/target pair is not supported by Apple Translation.
- `prepareTranslation() failed` — the system language-pack download prompt was cancelled or could not be shown.
- The hidden window is intentionally offscreen and almost transparent. If the language-pack prompt does not appear, try `--debug-window` once to make the host window slightly visible while testing.

Notes:

- The test input is `สวัสดีครับ วันนี้อากาศดีมาก` from Thai to English.
- The spike calls `LanguageAvailability.status(from:to:)` first and handles availability-check errors on newer SDKs where this API is `async throws`.
- If status is `supported` but not `installed`, the spike calls `prepareTranslation()` before translating so macOS can prompt for language asset download.

## Spike 2 — Clipboard-safe paste-back into the frontmost app

Goal: prove that translated text can be pasted into the app that was frontmost before the translation panel appeared, while preserving the user's existing clipboard.

Accessibility permission is required because this spike posts synthetic keyboard events.

Grant permission:

```text
System Settings > Privacy & Security > Accessibility
```

If you run with `swift run` from Terminal, grant Accessibility to Terminal, iTerm, or whatever shell host launches the process. If you run the compiled binary directly, grant the compiled binary or app wrapper.

Run:

```bash
swift run spike2-pasteback
```

Useful timing arguments:

```bash
swift run spike2-pasteback --paste-delay-ms 300
swift run spike2-pasteback --paste-delay-ms 600 --restore-delay-ms 500
swift run spike2-pasteback --capture-delay-ms 2000 --paste-delay-ms 300
```

CLI testing procedure with TextEdit:

1. Open TextEdit and create a new document.
2. Put the cursor in the document.
3. In Terminal, run:

   ```bash
   swift run spike2-pasteback --capture-delay-ms 2000 --paste-delay-ms 300
   ```

4. Immediately click back into TextEdit before the 2-second capture delay ends.
5. Verify `HELLO_FROM_SPIKE2` appears in TextEdit.
6. Verify your old clipboard contents are restored afterward.

Why `--capture-delay-ms` exists: when launched from Terminal, Terminal is normally the frontmost app at process start. The delay makes manual CLI testing possible by letting you focus TextEdit before the spike captures `NSWorkspace.shared.frontmostApplication`.

Expected output shape:

```text
SPIKE 2: Clipboard-safe paste-back into the frontmost app
INFO: Captured frontmost app before paste: TextEdit [pid=123]
INFO: Saved pasteboard items: 1, total types: 3
INFO: Wrote test string to pasteboard.
INFO: Requested re-activation of previous app: accepted
INFO: Posted Cmd+V via CGEvent to the HID event tap.
INFO: Restored original pasteboard contents after 300 ms. Verified: yes
PASS: Paste event was posted and the original pasteboard contents were restored. Manually verify "HELLO_FROM_SPIKE2" appeared in TextEdit.
```

Known failure modes:

- `Accessibility permission is not granted` — grant permission and re-run.
- Text appears in Terminal instead of TextEdit — use `--capture-delay-ms` and focus TextEdit before capture.
- No paste happens — increase `--paste-delay-ms` to `500` or `800` because focus restoration can race with the paste event.
- Clipboard not restored — this should be rare; the spike restores the saved pasteboard snapshot on both success and error paths.

Implementation details:

- Saves all current `NSPasteboardItem` objects and their available types/data.
- Writes `HELLO_FROM_SPIKE2` as `.string`.
- Re-activates the captured frontmost app with `NSRunningApplication.activate(options:)`.
- Posts Cmd+V using `CGEvent` to `.cghidEventTap`.
- Restores the original pasteboard after the configurable delay.

## Spike 3 — Non-activating floating input panel

Goal: prove that a floating input panel can accept typing without changing the frontmost app.

Run:

```bash
swift run spike3-panel
```

Default hotkey:

```text
Ctrl+Option+T
```

Custom hotkey examples:

```bash
swift run spike3-panel --hotkey ctrl+option+y
swift run spike3-panel --hotkey cmd+shift+t
```

Test procedure:

1. Open any app, for example Safari, TextEdit, Finder, or a fullscreen app.
2. Keep that app focused.
3. Press `Ctrl+Option+T`.
4. A floating panel should appear centered on the active screen.
5. Type any text into the panel.
6. Press Escape.
7. Confirm the console prints PASS, the previous app is still frontmost, and the spike exits after the first PASS/FAIL.

Expected output shape:

```text
SPIKE 3: Non-activating floating input panel
INFO: Hotkey: ctrl+option+t
INFO: Global hotkey registered. Keep another app focused, then press ctrl+option+t.
INFO: Frontmost before showing panel: TextEdit [pid=123]
INFO: Frontmost while panel is visible: TextEdit [pid=123]
INFO: Frontmost after hiding panel: TextEdit [pid=123]
INFO: Typed text captured by panel: yes
PASS: Previous app still has focus and the non-activating panel accepted keyboard input.
```

The spike terminates after this first PASS/FAIL result so it behaves like a standalone validation program rather than a long-running app.

Known failure modes:

- Hotkey does nothing — another app may own the hotkey. Try `--hotkey ctrl+option+y`.
- Panel appears but typing goes to the old app — non-activating panel key behavior failed; this is exactly what this spike is meant to validate on your target macOS/hardware.
- Panel does not appear over fullscreen app — check that `collectionBehavior` includes `.fullScreenAuxiliary` and test with a different fullscreen app/Space.
- Focus changes to the spike process — the non-activating panel behavior failed or a later UI change accidentally activated the app.

Implementation details:

- Uses `NSPanel` with `styleMask: [.nonactivatingPanel, .titled]`.
- Uses `level = .floating`.
- Uses `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- Registers a global hotkey with Carbon `RegisterEventHotKey`.
- Logs the frontmost app before showing and after hiding.
- Prints PASS only when typed text was captured and the frontmost app process matches.

## Real app — `translate-app`

A menu bar "type-to-translate" app combining Spike 1 (translation) and Spike 3 (non-activating panel), plus speech-to-text and clipboard copy. It does **not** use Spike 2's `CGEvent`/Accessibility auto-paste technique — see "Why not auto-paste" below.

Build and run as a proper `.app` bundle (needed for the microphone/speech-recognition permission prompts to work correctly):

```bash
./scripts/build-app.sh
open dist/Translate.app
```

This runs as an accessory app (no Dock icon) with an icon in the menu bar. It stays running until you choose Quit from the menu bar menu.

Flow:

1. Press the global hotkey (default `Ctrl+Option+T`) from any app.
2. A floating panel appears, centered on the active screen, without stealing focus from the app you were using.
3. Type/paste text, or click the mic button and speak, then press Enter (speaking auto-translates as soon as you stop).
4. The panel shows "Translating…", then the translated result.
5. Press Enter again to copy the translation to the clipboard — the panel shows "Copied ✓ — press ⌘V to paste" and closes. Paste it yourself wherever you need it. Press Escape at any point to cancel instead.

### Why not auto-paste?

Spike 2 proved that a `CGEvent`-simulated Cmd+V can paste into the previously-frontmost app automatically. The real app doesn't use that technique: it requires the Accessibility permission, which resets on every rebuild for an ad-hoc-signed dev binary (no paid Apple Developer certificate), and it's fundamentally incompatible with the Mac App Store's App Sandbox requirement — sandboxed apps cannot post synthetic input into other processes. Copying to the clipboard needs no special permission at all, works identically whether sandboxed or not, and is one keystroke away from the old behavior.

Menu bar menu:

- Shows the current hotkey.
- "Swap direction" toggles between the current source/target language pair (default `TH → EN`).
- Shows Microphone / Speech Recognition permission status, with shortcuts to open the relevant Settings pane.
- "Launch at Login" toggle (via `SMAppService`).
- Quit.

Known limitations:

- No language picker beyond swapping the current pair; other languages require editing `LanguagePair`'s default in `app/Sources/LanguagePair.swift`.
- No persisted settings — language pair and hotkey reset to defaults on relaunch.
- Speech input locale is derived from the two-letter source language code (see `SpeechInputService.localeIdentifier`); uncommon languages may need a mapping added.

## Suggested validation order

1. Run Spike 3 first to confirm the panel can accept typing without focus theft.
2. Run Spike 1 next because the Translation framework may require language assets to download.
3. Run Spike 2 only if you specifically want to validate the CGEvent auto-paste technique — the real app no longer uses it.

## What the spikes deliberately do not do

The three spikes (`spike1-translation/`, `spike2-pasteback/`, `spike3-panel/`) are isolated risk validations, not the app. Individually, they:

- Don't run as a menu bar app (`translate-app` does; see above).
- Don't persist settings.
- Don't offer a language picker UI.
- Don't auto-capture selected text.
- Don't replace global keyboard behavior.
- Don't fall back to a third-party translation provider.
- Aren't packaged for the Mac App Store.

`translate-app` lifts most of these limits (it is the menu bar app), but still has no persisted settings, no language picker beyond swap, no selected-text auto-capture, and no Mac App Store packaging — see "Known limitations" above.
