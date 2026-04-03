import Foundation
import Library

enum WorkingDirectoryManager {
    static var extensionBasePath: String {
        "/var/root/Library/Containers/\(AppConfiguration.systemExtensionBundleID)/Data"
    }

    static var extensionWorkingDirectoryPath: String {
        (extensionBasePath as NSString).appendingPathComponent("Working")
    }

    static var tempDirectoryPath: String {
        "/var/root/Library/Containers/\(AppConfiguration.systemExtensionBundleID)/Data/Temp"
    }

    static var helperBasePath: String {
        "/var/root/Library/Containers/\(AppConfiguration.rootHelperBundleID)/Data"
    }

    static var helperWorkingDirectoryPath: String {
        (helperBasePath as NSString).appendingPathComponent("Working")
    }

    static var helperTempDirectoryPath: String {
        (helperBasePath as NSString).appendingPathComponent("Temp")
    }

    static var helperNativeCrashBasePath: String {
        (helperBasePath as NSString).appendingPathComponent("NativeCrash")
    }

    static var extensionNativeCrashBasePath: String {
        "/var/root/Library/Containers/\(AppConfiguration.systemExtensionBundleID)/Data/NativeCrash"
    }

    static var extensionOOMReportsPath: String {
        (extensionWorkingDirectoryPath as NSString).appendingPathComponent("oom_reports")
    }

    static func getSize() -> Int64 {
        let path = extensionWorkingDirectoryPath
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
        let path = extensionWorkingDirectoryPath
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
