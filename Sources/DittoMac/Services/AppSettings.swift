import Foundation

enum AppSettings {
    private static let defaults = UserDefaults.standard

    /// nil means "explicitly cleared by the user" (not "never customized") — distinct from an
    /// absent key, which falls back to the default. The menu bar icon click always opens the
    /// popup regardless, so clearing this can't lock anyone out.
    static var toggleHotKey: KeyCombo? {
        get {
            guard !defaults.bool(forKey: "toggleHotKeyCleared") else { return nil }
            return decode("toggleHotKey") ?? .defaultToggle
        }
        set {
            if let newValue {
                defaults.set(false, forKey: "toggleHotKeyCleared")
                encode(newValue, forKey: "toggleHotKey")
            } else {
                defaults.set(true, forKey: "toggleHotKeyCleared")
            }
        }
    }

    static func quickPasteHotKey(slot: Int) -> KeyCombo {
        decode("quickPasteHotKey.\(slot)") ?? .defaultQuickPaste(slot: slot)
    }

    private static func decode(_ key: String) -> KeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private static func encode(_ combo: KeyCombo, forKey key: String) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }
}
