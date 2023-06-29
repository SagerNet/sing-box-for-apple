import Foundation

public enum FilePath {
    public static let packageName = "io.nekohasekai.sfa"
    #if os(iOS)
        public static let httpClientName = "SFI"
    #elseif os(macOS)
        public static let httpClientName = "SFM"
    #endif
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

    static let sharedDirectory: URL! = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)

    static let cacheDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)

    static let iCloudDirectory = FileManager.default.url(forUbiquityContainerIdentifier: nil)!.appendingPathComponent("Documents", isDirectory: true)
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
