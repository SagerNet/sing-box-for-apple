import Foundation

public enum SharedPreferences {
    public static let selectedProfileID = Preference<Int64>("selected_profile_id", defaultValue: -1)

    #if os(macOS)
        private static let disableMemoryLimitByDefault = true
    #else
        private static let disableMemoryLimitByDefault = false
    #endif

    public static let disableMemoryLimit = Preference<Bool>("disable_memory_limit", defaultValue: disableMemoryLimitByDefault)

    #if !os(tvOS)
        public static let includeAllNetworks = Preference<Bool>("include_all_networks", defaultValue: false)
    #endif

    public static let maxLogLines = Preference<Int>("max_log_lines", defaultValue: 300)
    public static let alwaysOn = Preference<Bool>("always_on", defaultValue: false)
    public static let ignoreDeviceSleep = Preference<Bool>("ignore_device_sleep", defaultValue: false)

    #if os(macOS)
        public static let showMenuBarExtra = Preference<Bool>("show_menu_bar_extra", defaultValue: true)
        public static let menuBarExtraInBackground = Preference<Bool>("menu_bar_extra_in_background", defaultValue: false)
        public static let startedByUser = Preference<Bool>("started_by_user", defaultValue: false)
    #endif

    #if os(iOS)
        public static let networkPermissionRequested = Preference<Bool>("network_permission_requested", defaultValue: false)
    #endif

    public static let systemProxyEnabled = Preference<Bool>("system_proxy_enabled", defaultValue: true)
}
