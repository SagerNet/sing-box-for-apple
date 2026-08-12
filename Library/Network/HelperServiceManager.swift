#if os(macOS)
    import AppKit
    import Foundation
    import os
    import ServiceManagement

    private let logger = Logger(category: "HelperServiceManager")

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

        public static func openApprovalSettings() {
            if #available(macOS 13.0, *) {
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users?LoginItems"),
               NSWorkspace.shared.open(url)
            {
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
        }

        public static func updateRootHelperIfNeeded() async {
            guard rootHelperStatus == .enabled else { return }

            do {
                let installedVersion = try ShellHelperClient.shared.getVersion()
                let currentVersion = Bundle.main.version
                guard currentVersion != installedVersion else { return }
            } catch {
                logger.warning("Failed to get root helper version, updating: \(error.localizedDescription)")
            }

            do {
                try unregisterRootHelper()
                try await Task.sleep(for: .seconds(1))
                try registerRootHelper()
            } catch {
                logger.error("Failed to update root helper: \(error.localizedDescription)")
            }
        }
    }
#endif
