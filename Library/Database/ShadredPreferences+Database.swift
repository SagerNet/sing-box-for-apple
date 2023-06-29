import BinaryCodable
import Foundation
import GRDB

extension SharedPreferences {
    @propertyWrapper public class Preference<T: Codable> {
        private let name: String
        private let defaultValue: T

        init(_ name: String, defaultValue: T) {
            self.name = name
            self.defaultValue = defaultValue
        }

        public var wrappedValue: T {
            get {
                do {
                    return try SharedPreferences.read(name) ?? defaultValue
                } catch {
                    NSLog("read preferences error: \(error)")
                    return defaultValue
                }
            }
            set {
                do {
                    try SharedPreferences.write(name, newValue)
                } catch {
                    NSLog("write preferences error: \(error)")
                }
            }
        }
    }

    @propertyWrapper public class NullablePreference<T: Codable> {
        private let name: String

        init(_ name: String) {
            self.name = name
        }

        public var wrappedValue: T? {
            get {
                do {
                    return try SharedPreferences.read(name)
                } catch {
                    NSLog("read preferences error: \(error)")
                    return nil
                }
            }
            set {
                do {
                    try SharedPreferences.write(name, newValue)
                } catch {
                    NSLog("write preferences error: \(error)")
                }
            }
        }
    }

    private static func read<T: Codable>(_ name: String) throws -> T? {
        guard let item = try (Database.sharedWriter().read { db in
            try Item.fetchOne(db, id: name)
        })
        else {
            return nil
        }
        return try BinaryDecoder().decode(from: item.data)
    }

    private static func write(_ name: String, _ value: (some Codable)?) throws {
        if value == nil {
            _ = try Database.sharedWriter().write { db in
                try Item.deleteOne(db, id: name)
            }
        } else {
            let data = try BinaryEncoder().encode(value)
            try Database.sharedWriter().write { db in
                try Item(name: name, data: data).insert(db)
            }
        }
    }
}

private class Item: Record, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    public var data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
        super.init()
    }

    override public class var databaseTableName: String {
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

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.name] = name
        container[Columns.data] = data
    }
}
