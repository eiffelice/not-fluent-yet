import Carbon.HIToolbox

struct HotKey {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let description: String

    static let `default` = HotKey(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | optionKey),
        description: "ctrl+option+t"
    )
}
