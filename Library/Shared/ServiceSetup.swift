import Foundation
import Libbox

public enum ServiceSetup {
    public static func apply(crashReportSource: String) throws {
        let options = LibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.relativePath
        options.workingPath = FilePath.workingDirectory.relativePath
        options.tempPath = FilePath.cacheDirectory.relativePath
        options.crashReportSource = crashReportSource
        var error: NSError?
        LibboxSetup(options, &error)
        if let error {
            throw error
        }
    }
}
