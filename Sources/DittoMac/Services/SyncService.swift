import Combine
import CryptoKit
import Foundation
import Network

/// Peer-to-peer LAN clipboard sync, modeled after Ditto's "sync group" feature: no cloud
/// involved, peers discover each other via Bonjour on the local network and must be
/// explicitly trusted before items are exchanged. Payloads are encrypted with a key derived
/// from a shared passphrase set by the user.
final class SyncService: ObservableObject {
    static let serviceType = "_dittomac._tcp"

    struct DiscoveredPeer: Identifiable, Equatable {
        let id: String
        let endpoint: NWEndpoint
        let name: String
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "syncEnabled")
            isEnabled ? start() : stop()
        }
    }
    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published private(set) var connectedPeerIDs: Set<String> = []

    let localPeerID: String
    var localDisplayName: String { Host.current().localizedName ?? "This Mac" }

    private weak var store: ClipboardStore?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.dittomac.sync")

    private var passphrase: String {
        get { UserDefaults.standard.string(forKey: "syncPassphrase") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "syncPassphrase") }
    }

    private var symmetricKey: SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(passphrase.utf8)))
    }

    init(store: ClipboardStore) {
        self.store = store
        self.isEnabled = UserDefaults.standard.bool(forKey: "syncEnabled")

        if let existing = UserDefaults.standard.string(forKey: "localPeerID") {
            localPeerID = existing
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "localPeerID")
            localPeerID = newID
        }

        store.onNewLocalItem = { [weak self] item in
            self?.broadcast(item)
        }

        if isEnabled { start() }
    }

    func setPassphrase(_ value: String) { passphrase = value }
    func currentPassphrase() -> String { passphrase }

    // MARK: - Lifecycle

    func start() {
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        for (_, connection) in connections { connection.cancel() }
        connections.removeAll()
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll()
            self.connectedPeerIDs.removeAll()
        }
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: localPeerID, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                self?.setup(connection, key: UUID().uuidString, isIncoming: true)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("DittoMac sync listener failed: \(error)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("DittoMac: failed to start sync listener: \(error)")
        }
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let peers: [DiscoveredPeer] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint, name != self.localPeerID else { return nil }
                return DiscoveredPeer(id: name, endpoint: result.endpoint, name: name)
            }
            DispatchQueue.main.async { self.discoveredPeers = peers }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// Explicitly initiate a connection to a discovered peer (user-approved pairing).
    func connect(to peer: DiscoveredPeer) {
        let connection = NWConnection(to: peer.endpoint, using: .tcp)
        setup(connection, key: peer.id, isIncoming: false)
    }

    private func setup(_ connection: NWConnection, key: String, isIncoming: Bool) {
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.connectedPeerIDs.insert(key) }
                self.sendHello(on: connection)
            case .failed, .cancelled:
                self.connections.removeValue(forKey: key)
                DispatchQueue.main.async { self.connectedPeerIDs.remove(key) }
            default:
                break
            }
        }
        receiveLoop(on: connection)
        connection.start(queue: queue)
    }

    // MARK: - Messaging

    private enum MessageType: String, Codable { case hello, clipItem }

    private struct WireMessage: Codable {
        var type: MessageType
        var peerID: String
        var displayName: String
        var item: WireClipItem?
    }

    private struct WireClipItem: Codable {
        var createdAt: Date
        var type: ClipItemType
        var textContent: String?
        var rtfData: Data?
        var imageData: Data?
        var fileURLsJoined: String?
        var htmlContent: String?
        var sourceAppName: String?
    }

    private func sendHello(on connection: NWConnection) {
        let message = WireMessage(type: .hello, peerID: localPeerID, displayName: localDisplayName, item: nil)
        send(message, on: connection)
    }

    private func broadcast(_ item: ClipItem) {
        guard isEnabled, !passphrase.isEmpty, !connections.isEmpty else { return }
        let wireItem = WireClipItem(
            createdAt: item.createdAt, type: item.type, textContent: item.textContent, rtfData: item.rtfData,
            imageData: item.imageData, fileURLsJoined: item.fileURLsJoined, htmlContent: item.htmlContent,
            sourceAppName: item.sourceAppName
        )
        let message = WireMessage(type: .clipItem, peerID: localPeerID, displayName: localDisplayName, item: wireItem)
        for (_, connection) in connections {
            send(message, on: connection)
        }
    }

    private func send(_ message: WireMessage, on connection: NWConnection) {
        guard !passphrase.isEmpty, let payload = try? JSONEncoder().encode(message) else { return }
        guard let sealed = try? AES.GCM.seal(payload, using: symmetricKey).combined else { return }
        var lengthPrefix = UInt32(sealed.count).bigEndian
        var frame = Data(bytes: &lengthPrefix, count: 4)
        frame.append(sealed)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4, error == nil else { return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 20_000_000 else { return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] body, _, _, error in
                guard let self, let body, error == nil else { return }
                self.handle(body, on: connection)
                self.receiveLoop(on: connection)
            }
        }
    }

    private func handle(_ encrypted: Data, on connection: NWConnection) {
        guard !passphrase.isEmpty,
              let sealedBox = try? AES.GCM.SealedBox(combined: encrypted),
              let payload = try? AES.GCM.open(sealedBox, using: symmetricKey),
              let message = try? JSONDecoder().decode(WireMessage.self, from: payload) else { return }

        switch message.type {
        case .hello:
            break
        case .clipItem:
            guard let wire = message.item else { return }
            let item = ClipItem(
                createdAt: wire.createdAt, type: wire.type, textContent: wire.textContent, rtfData: wire.rtfData,
                imageData: wire.imageData, fileURLsJoined: wire.fileURLsJoined, htmlContent: wire.htmlContent,
                sourceBundleID: nil, sourceAppName: wire.sourceAppName, isPinned: false, groupID: nil,
                syncOrigin: message.peerID
            )
            DispatchQueue.main.async { [weak self] in
                self?.store?.receiveRemoteItem(item)
            }
        }
    }
}
