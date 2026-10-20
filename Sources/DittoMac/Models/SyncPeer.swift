import Foundation
import GRDB

struct SyncPeer: Identifiable, Codable, Equatable {
    var id: Int64?
    var peerID: String
    var displayName: String
    var trusted: Bool
}

extension SyncPeer: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "syncPeer"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let peerID = Column(CodingKeys.peerID)
        static let trusted = Column(CodingKeys.trusted)
    }
}
