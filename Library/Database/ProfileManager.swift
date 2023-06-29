import Foundation
import GRDB

public enum ProfileManager {
    public static func create(_ profile: Profile) throws {
        profile.order = try nextOrder()
        try Database.sharedWriter().write { db in
            try profile.insert(db, onConflict: .fail)
        }
    }

    public static func get(_ profileID: Int64) throws -> Profile? {
        try Database.sharedWriter().read { db in
            try Profile.fetchOne(db, id: profileID)
        }
    }

    public static func get(by profileName: String) throws -> Profile? {
        try Database.sharedWriter().read { db in
            try Profile.filter(Column("name") == profileName).fetchOne(db)
        }
    }

    public static func delete(_ profile: Profile) throws {
        _ = try Database.sharedWriter().write { db in
            try profile.delete(db)
        }
    }

    public static func delete(by id: Int64) throws {
        _ = try Database.sharedWriter().write { db in
            try Profile.deleteOne(db, id: id)
        }
    }

    public static func delete(_ profileList: [Profile]) throws -> Int {
        try Database.sharedWriter().write { db in
            try Profile.deleteAll(db, keys: profileList.map {
                ["id": $0.id!]
            })
        }
    }

    public static func delete(by id: [Int64]) throws -> Int {
        try Database.sharedWriter().write { db in
            try Profile.deleteAll(db, ids: id)
        }
    }

    public static func update(_ profile: Profile) throws {
        _ = try Database.sharedWriter().write { db in
            try profile.updateChanges(db)
        }
    }

    public static func update(_ profileList: [Profile]) throws {
        // TODO: batch update
        try Database.sharedWriter().write { db in
            for profile in profileList {
                try profile.updateChanges(db)
            }
        }
    }

    public static func list() throws -> [Profile] {
        try Database.sharedWriter().read { db in
            try Profile.all().order(Column("order").asc).fetchAll(db)
        }
    }

    public static func listRemote() throws -> [Profile] {
        try Database.sharedWriter().read { db in
            try Profile.filter(Column("type") == ProfileType.remote.rawValue).order(Column("order").asc).fetchAll(db)
        }
    }

    public static func listAutoUpdateEnabled() throws -> [Profile] {
        try Database.sharedWriter().read { db in
            try Profile.filter(Column("autoUpdate") == true).order(Column("order").asc).fetchAll(db)
        }
    }

    public static func nextID() throws -> Int64 {
        try Database.sharedWriter().read { db in
            if let lastProfile = try Profile.select(Column("id")).order(Column("id").desc).fetchOne(db) {
                return lastProfile.id! + 1
            } else {
                return 1
            }
        }
    }

    private static func nextOrder() throws -> UInt32 {
        try Database.sharedWriter().read { db in
            try UInt32(Profile.fetchCount(db))
        }
    }
}
