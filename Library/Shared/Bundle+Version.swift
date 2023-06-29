import Foundation

extension Bundle {
    var version: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var versionNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
