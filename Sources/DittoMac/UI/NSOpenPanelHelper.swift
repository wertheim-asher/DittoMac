import AppKit

enum NSOpenPanelHelper {
    /// Presents an NSOpenPanel scoped to /Applications and returns (bundleID, displayName) for the chosen app.
    static func chooseApplication() -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return (bundleID, name)
    }
}
