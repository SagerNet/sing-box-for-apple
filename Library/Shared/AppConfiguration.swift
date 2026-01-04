import Foundation

public enum AppConfiguration {
    public static let packageName: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BasePackageIdentifier") as? String else {
            fatalError("Missing BasePackageIdentifier in Info.plist")
        }
        return value
    }()

    public static let appGroupID: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else {
            fatalError("Missing AppGroupIdentifier in Info.plist")
        }
        return value
    }()

    public static var teamID: String {
        guard let dotIndex = appGroupID.firstIndex(of: ".") else {
            fatalError("Invalid appGroupID format: \(appGroupID)")
        }
        return String(appGroupID[..<dotIndex])
    }

    public static var extensionBundleID: String { "\(packageName).extension" }
    public static var systemExtensionBundleID: String { "\(packageName).system" }
    public static var fileProviderDomainID: String { "\(packageName).workingdir" }
    public static var widgetControlKind: String { "\(packageName).widget.ServiceToggle" }
    public static var profileUTType: String { "\(packageName).profile" }
    public static var backgroundTaskID: String { "\(packageName).update_profiles" }
    public static var iCloudContainerID: String { "iCloud.\(packageName)" }

    #if os(macOS)
        public static var rootHelperBundleID: String { "\(packageName).helper" }
        public static var rootHelperMachService: String { "\(appGroupID).helper" }
    #endif
}
