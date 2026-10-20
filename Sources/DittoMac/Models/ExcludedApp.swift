import Foundation
import GRDB

struct ExcludedApp: Identifiable, Codable, Equatable {
    var id: Int64?
    var bundleID: String
    var appName: String
}

extension ExcludedApp: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "excludedApp"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let bundleID = Column(CodingKeys.bundleID)
        static let appName = Column(CodingKeys.appName)
    }
}
