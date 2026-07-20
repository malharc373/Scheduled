import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon. `RegisterEventHotKey` does NOT
/// require Accessibility permission, which keeps first-run friction low.
/// Default binding: ⌘⌃J.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// keyCode 38 == J. Modifiers default to Command+Control.
    func register(keyCode: UInt32 = 38,
                  modifiers: UInt32 = UInt32(cmdKey | controlKey)) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                GlobalHotKey.shared.onPress?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        let id = EventHotKeyID(signature: OSType(0x5343484C) /* 'SCHL' */, id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
