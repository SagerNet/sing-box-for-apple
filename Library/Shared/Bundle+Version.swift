import Foundation

public extension Bundle {
    var version: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var versionNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    static var application: Bundle {
        var currentURL = main.bundleURL
        while currentURL.path != "/" {
            if currentURL.pathExtension.lowercased() == "app" {
                return Bundle(url: currentURL) ?? main
            }
            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL == currentURL {
                break
            }
            currentURL = parentURL
        }
        return main
    }
}
