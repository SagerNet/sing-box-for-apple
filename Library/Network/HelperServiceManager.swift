#if os(macOS)
    import Foundation
    import ServiceManagement

    public enum HelperServiceManager {
        private static var rootHelperService: SMAppService {
            SMAppService.daemon(plistName: "\(AppConfiguration.rootHelperBundleID).plist")
        }

        public static var rootHelperStatus: SMAppService.Status {
            rootHelperService.status
        }

        public static func registerRootHelper() throws {
            if rootHelperService.status == .enabled {
                try rootHelperService.unregister()
            }
            try rootHelperService.register()
        }

        public static func unregisterRootHelper() throws {
            try rootHelperService.unregister()
        }
    }
#endif
