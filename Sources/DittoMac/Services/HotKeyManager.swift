import Carbon.HIToolbox
import Foundation

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask (controlKey, optionKey, cmdKey, shiftKey)

    static let defaultToggle = KeyCombo(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey))

    static func defaultQuickPaste(slot: Int) -> KeyCombo {
        let digitCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5),
            UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9), UInt32(kVK_ANSI_0)
        ]
        let code = digitCodes[(slot - 1) % 10]
        return KeyCombo(keyCode: code, modifiers: UInt32(controlKey | optionKey))
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0 { s += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0 { s += "\u{21E7}" }
        if modifiers & UInt32(cmdKey) != 0 { s += "\u{2318}" }
        s += KeyCombo.keyCodeName(keyCode)
        return s
    }

    static func keyCodeName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_ANSI_0): "0", UInt32(kVK_Space): "Space"
        ]
        return names[keyCode] ?? "?"
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8 { result = (result << 8) + OSType(char) }
    return result
}

/// Thin wrapper around the Carbon global hotkey API (still the only way to register
/// system-wide hotkeys outside the Accessibility/Input Monitoring event-tap approach).
final class HotKeyManager {
    typealias Handler = () -> Void

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: Handler] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let signature = fourCharCode("DTMC")

    static let toggleID: UInt32 = 1
    static func quickPasteID(slot: Int) -> UInt32 { UInt32(100 + slot) }

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }

    @discardableResult
    func register(id: UInt32, combo: KeyCombo, handler: @escaping Handler) -> Bool {
        unregister(id: id)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, let ref = hotKeyRef else { return false }
        hotKeyRefs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard err == noErr else { return err }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }
}
