import Foundation
import Library

enum WorkingDirectoryManager {
    private static var workingDirectoryPath: String {
        "/var/root/Library/Containers/\(AppConfiguration.systemExtensionBundleID)/Data/Working"
    }

    static func getSize() -> Int64 {
        let path = workingDirectoryPath
        guard FileManager.default.fileExists(atPath: path) else {
            return 0
        }

        var totalSize: Int64 = 0
        let enumerator = FileManager.default.enumerator(atPath: path)

        while let file = enumerator?.nextObject() as? String {
            let filePath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int64
            {
                totalSize += size
            }
        }

        return totalSize
    }

    static func clean() throws {
        let path = workingDirectoryPath
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            try FileManager.default.removeItem(atPath: itemPath)
        }
    }
}
