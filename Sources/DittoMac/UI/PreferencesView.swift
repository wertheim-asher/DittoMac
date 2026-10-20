import SwiftUI

struct PreferencesView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var syncService: SyncService
    let onHotKeysChanged: () -> Void
    let onHotKeyRecordingChanged: (Bool) -> Void

    private enum Tab { case general, groups, excludedApps, sync }
    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(store: store, onHotKeysChanged: onHotKeysChanged, onHotKeyRecordingChanged: onHotKeyRecordingChanged)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            GroupsTab(store: store)
                .tabItem { Label("Groups", systemImage: "folder") }
                .tag(Tab.groups)
            ExcludedAppsTab(store: store)
                .tabItem { Label("Excluded Apps", systemImage: "eye.slash") }
                .tag(Tab.excludedApps)
            SyncTab(syncService: syncService)
                .tabItem { Label("LAN Sync", systemImage: "network") }
                .tag(Tab.sync)
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .onChange(of: store.preferencesOpenCount) { _ in selectedTab = .general }
    }
}

private struct GeneralTab: View {
    @ObservedObject var store: ClipboardStore
    let onHotKeysChanged: () -> Void
    let onHotKeyRecordingChanged: (Bool) -> Void

    @State private var toggleCombo = AppSettings.toggleHotKey
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var maxItems: Int
    @State private var maxAgeDays: Int

    private let maxItemsRange = 25...5000
    private let maxAgeDaysRange = 0...365 // 0 = never

    init(store: ClipboardStore, onHotKeysChanged: @escaping () -> Void, onHotKeyRecordingChanged: @escaping (Bool) -> Void) {
        self.store = store
        self.onHotKeysChanged = onHotKeysChanged
        self.onHotKeyRecordingChanged = onHotKeyRecordingChanged
        _maxItems = State(initialValue: store.maxItems)
        _maxAgeDays = State(initialValue: store.maxAgeDays)
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch DittoMac at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in LoginItemManager.setEnabled(newValue) }
            }

            Section("Open DittoMac Shortcut") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard shortcut")
                        Text("Press this combination anywhere to open the clipboard history popup. Press Delete while recording to remove it — the menu bar icon always opens the popup too.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotKeyRecorderField(combo: $toggleCombo, onRecordingChanged: onHotKeyRecordingChanged)
                        .onChange(of: toggleCombo) { newValue in
                            AppSettings.toggleHotKey = newValue
                            onHotKeysChanged()
                        }
                }
            }

            Section("History") {
                HStack {
                    Text("Max items kept")
                    Spacer()
                    TextField("", value: $maxItems, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("(\(maxItemsRange.lowerBound)–\(maxItemsRange.upperBound))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: maxItems) { newValue in
                    let clamped = min(max(newValue, maxItemsRange.lowerBound), maxItemsRange.upperBound)
                    if clamped != newValue { maxItems = clamped }
                    store.maxItems = clamped
                }

                HStack {
                    Text("Auto-purge after")
                    Spacer()
                    TextField("", value: $maxAgeDays, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text(maxAgeDays == 0 ? "days (0 = never)" : "days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: maxAgeDays) { newValue in
                    let clamped = min(max(newValue, maxAgeDaysRange.lowerBound), maxAgeDaysRange.upperBound)
                    if clamped != newValue { maxAgeDays = clamped }
                    store.maxAgeDays = clamped
                }
            }

            Section {
                Button("Clear Unpinned History", role: .destructive) {
                    store.clearAll(keepPinned: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GroupsTab: View {
    @ObservedObject var store: ClipboardStore
    @State private var newGroupName = ""

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(store.groups) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Button {
                            store.deleteGroup(group)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("New group name", text: $newGroupName)
                    .onSubmit { addGroupIfValid() }
                Button("Add") {
                    addGroupIfValid()
                }
            }
        }
    }

    private func addGroupIfValid() {
        guard !newGroupName.isEmpty else { return }
        store.addGroup(named: newGroupName)
        newGroupName = ""
    }
}

private struct ExcludedAppsTab: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading) {
            Text("Copies made from these apps won't be saved to history — useful for password managers.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(store.excludedApps) { app in
                    HStack {
                        Text(app.appName)
                        Spacer()
                        Button("Remove") { store.removeExcludedApp(app) }
                    }
                }
            }
            Button("Add App…") {
                let panel = NSOpenPanelHelper.chooseApplication()
                if let (bundleID, name) = panel {
                    store.addExcludedApp(bundleID: bundleID, appName: name)
                }
            }
        }
    }
}

private struct SyncTab: View {
    @ObservedObject var syncService: SyncService
    @State private var passphrase: String = ""

    var body: some View {
        Form {
            Section("LAN Sync Group") {
                Toggle("Enable LAN sync", isOn: $syncService.isEnabled)
                Text("Peer-to-peer only — no cloud, no account. Every Mac in the group must use the same passphrase and be on the same local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Shared passphrase", text: $passphrase)
                    .onAppear { passphrase = syncService.currentPassphrase() }
                    .onChange(of: passphrase) { newValue in syncService.setPassphrase(newValue) }
            }

            Section("Discovered Peers") {
                if syncService.discoveredPeers.isEmpty {
                    Text("No peers found yet.").foregroundStyle(.secondary)
                }
                ForEach(syncService.discoveredPeers) { peer in
                    HStack {
                        Text(peer.name)
                        Spacer()
                        if syncService.connectedPeerIDs.contains(peer.id) {
                            Text("Connected").foregroundStyle(.secondary)
                        } else {
                            Button("Connect") { syncService.connect(to: peer) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
