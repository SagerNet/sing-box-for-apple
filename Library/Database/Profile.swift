import Foundation
import GRDB

public class Profile: Record, Identifiable, ObservableObject {
    public var id: Int64?
    public var mustID: Int64 {
        id!
    }

    @Published public var name: String
    public var order: UInt32
    public var type: ProfileType
    public var path: String
    @Published public var remoteURL: String?
    @Published public var autoUpdate: Bool
    public var lastUpdated: Date?

    public init(id: Int64? = nil, name: String, order: UInt32 = 0, type: ProfileType, path: String, remoteURL: String? = nil, lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.type = type
        self.path = path
        self.remoteURL = remoteURL
        self.lastUpdated = lastUpdated

        autoUpdate = false
        super.init()
    }

    override public class var databaseTableName: String {
        "profiles"
    }

    enum Columns: String, ColumnExpression {
        case id, name, order, type, path, remoteURL, autoUpdate, lastUpdated, userAgent
    }

    required init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name] ?? ""
        order = row[Columns.order] ?? 0
        type = ProfileType(rawValue: row[Columns.type] ?? ProfileType.local.rawValue)!
        path = row[Columns.path] ?? ""
        remoteURL = row[Columns.remoteURL] ?? ""
        autoUpdate = row[Columns.autoUpdate] ?? false
        lastUpdated = row[Columns.lastUpdated] ?? Date()
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.order] = order
        container[Columns.type] = type.rawValue
        container[Columns.path] = path
        container[Columns.remoteURL] = remoteURL
        container[Columns.autoUpdate] = autoUpdate
        container[Columns.lastUpdated] = lastUpdated
    }

    override public func didInsert(_ inserted: InsertionSuccess) {
        super.didInsert(inserted)
        id = inserted.rowID
    }
}

public enum ProfileType: Int {
    case local = 0, icloud, remote
}
