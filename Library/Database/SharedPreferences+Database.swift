import BinaryCodable
import Foundation
import GRDB

extension SharedPreferences {
    public class Preference<T: Codable> {
        let name: String
        private let defaultValue: T

        init(_ name: String, defaultValue: T) {
            self.name = name
            self.defaultValue = defaultValue
        }

        public nonisolated func get() async -> T {
            do {
                return try await SharedPreferences.read(name) ?? defaultValue
            } catch {
                NSLog("read preferences error: \(error)")
                return defaultValue
            }
        }

        public func getBlocking() -> T {
            runBlocking { [self] in
                await get()
            }
        }

        public nonisolated func set(_ newValue: T?) async {
            do {
                try await SharedPreferences.write(name, newValue)
            } catch {
                NSLog("write preferences error: \(error)")
            }
        }
    }

    private nonisolated static func read<T: Codable>(_ name: String) async throws -> T? {
        guard let item = try await (Database.sharedWriter.read { db in
            try Item.fetchOne(db, id: name)
        })
        else {
            return nil
        }
        if T.self == String.self {
            return String(data: item.data, encoding: .utf8) as? T
        } else {
            return try BinaryDecoder().decode(from: item.data)
        }
    }

    private nonisolated static func write(_ name: String, _ value: (some Codable)?) async throws {
        if value == nil {
            _ = try await Database.sharedWriter.write { db in
                try Item.deleteOne(db, id: name)
            }
        } else {
            let data: Data
            if let stringValue = value as? String {
                data = stringValue.data(using: .utf8)!
            } else {
                data = try BinaryEncoder().encode(value)
            }
            try await Database.sharedWriter.write { db in
                try Item(name: name, data: data).save(db)
            }
        }
    }

    nonisolated static func batchDelete(_ names: [String]) async throws {
        try await Database.sharedWriter.write { db in
            for name in names {
                try Item.deleteOne(db, id: name)
            }
        }
    }
}

private class Item: Record, Identifiable {
    var id: String {
        name
    }

    var name: String
    var data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
        super.init()
    }

    override class var databaseTableName: String {
        "preferences"
    }

    enum Columns: String, ColumnExpression {
        case name, data
    }

    required init(row: Row) throws {
        name = row[Columns.name]
        data = row[Columns.data]
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) throws {
        container[Columns.name] = name
        container[Columns.data] = data
    }
}
