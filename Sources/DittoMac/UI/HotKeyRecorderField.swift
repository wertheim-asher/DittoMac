import Carbon.HIToolbox
import SwiftUI

/// A click-to-record hotkey field, implemented as a plain SwiftUI view rather than a wrapped
/// NSView — an NSViewRepresentable version of this kept causing Form/Section row-height
/// measurement to collapse, hiding its own label and neighboring rows.
struct HotKeyRecorderField: View {
    /// nil means no shortcut is assigned — pressing Delete while recording clears it to this.
    @Binding var combo: KeyCombo?
    /// Fired with `true` when the user starts recording and `false` when they finish (or cancel
    /// by clicking away). The caller should temporarily unregister its global hotkeys while
    /// `true` — otherwise the *currently bound* combo still fires system-wide while the user is
    /// in the middle of pressing keys to replace it, e.g. opening the popup instead of just
    /// recording it.
    var onRecordingChanged: ((Bool) -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?

    private static let deleteKeyCode: UInt16 = 51

    var body: some View {
        Button(action: startRecording) {
            Text(displayText)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private var displayText: String {
        if isRecording { return "Press keys… (⌫ to clear)" }
        return combo?.displayString ?? "Click here to add a shortcut"
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChanged?(true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == Self.deleteKeyCode {
                combo = nil
                stopRecording()
                return nil
            }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChanged?(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
