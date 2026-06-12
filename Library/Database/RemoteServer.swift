import Foundation
import GRDB

public class RemoteServer: Record, Identifiable, ObservableObject {
    public var id: Int64?
    public var mustID: Int64 {
        id!
    }

    @Published public var name: String?
    public var order: UInt32
    @Published public var url: String
    @Published public var secret: String

    public var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return url
    }

    public init(
        id: Int64? = nil,
        name: String? = nil,
        order: UInt32 = 0,
        url: String = "",
        secret: String = ""
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.url = url
        self.secret = secret
        super.init()
    }

    override public class var databaseTableName: String {
        "remote_servers"
    }

    enum Columns: String, ColumnExpression {
        case id, name, order, url, secret
    }

    required init(row: Row) throws {
        id = row[Columns.id]
        let storedName: String = row[Columns.name] ?? ""
        name = storedName.isEmpty ? nil : storedName
        order = row[Columns.order] ?? 0
        url = row[Columns.url] ?? ""
        secret = row[Columns.secret] ?? ""
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        // The column is NOT NULL; a missing name is stored as "".
        container[Columns.name] = name ?? ""
        container[Columns.order] = order
        container[Columns.url] = url
        container[Columns.secret] = secret
    }

    override public func didInsert(_ inserted: InsertionSuccess) {
        super.didInsert(inserted)
        id = inserted.rowID
    }
}

public extension RemoteServer {
    /// Validates a server URL: `host[:port]`, `http://host[:port]` or
    /// `https://host[:port]`. A missing scheme is normalized to `http://`.
    static func validateURL(_ urlString: String) throws -> String {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            throw NSError(domain: "RemoteServer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Invalid server URL: \(urlString), expected host:port, http://host:port or https://host:port"),
            ])
        }
        return trimmed
    }
}
