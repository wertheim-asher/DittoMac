import Foundation
import GRDB

struct ClipGroup: Identifiable, Codable, Equatable {
    var id: Int64?
    var name: String
    var sortOrder: Int
}

extension ClipGroup: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clipGroup"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}
