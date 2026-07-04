import Carbon.HIToolbox
import AppKit

@MainActor
final class HotKeyManager {
    private let hotkey: HotKey
    private let onPress: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(hotkey: HotKey, onPress: @escaping () -> Void) {
        self.hotkey = hotkey
        self.onPress = onPress
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    @discardableResult
    func register() -> Bool {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("TRAP"), id: 1)

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.onPress()
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
            return false
        }

        let registerStatus = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            print("FAIL: RegisterEventHotKey failed with OSStatus \(registerStatus). The hotkey may be reserved by another app.")
            return false
        }

        print("INFO: Global hotkey registered: \(hotkey.description)")
        return true
    }
}

func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
