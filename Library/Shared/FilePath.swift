import Foundation

public enum FilePath {
    public static let packageName = "io.nekohasekai.sfa"
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

    static var sharedDirectory = defaultSharedDirectory

    private static var defaultSharedDirectory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)!
    }

    static var cacheDirectory: URL {
        sharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    }

    static var workingDirectory: URL {
        cacheDirectory.appendingPathComponent("Working", isDirectory: true)
    }

    static var iCloudDirectory: URL {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)!.appendingPathComponent("Documents", isDirectory: true)
    }
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
