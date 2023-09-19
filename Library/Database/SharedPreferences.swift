import Foundation

public enum SharedPreferences {
    @Preference<Int64>("selected_profile_id", defaultValue: -1) public static var selectedProfileID

    #if os(macOS)
        private static let disableMemoryLimitByDefault = true
    #else
        private static let disableMemoryLimitByDefault = false
    #endif
    @Preference<Bool>("disable_memory_limit", defaultValue: disableMemoryLimitByDefault) public static var disableMemoryLimit
    @Preference<Bool>("include_all_networks", defaultValue: false) public static var includeAllNetworks

    @Preference<Int>("max_log_lines", defaultValue: 300) public static var maxLogLines
    @Preference<Bool>("always_on", defaultValue: false) public static var alwaysOn

    #if os(macOS)
        @Preference<Bool>("show_menu_bar_extra", defaultValue: true) public static var showMenuBarExtra
        @Preference<Bool>("menu_bar_extra_in_background", defaultValue: false) public static var menuBarExtraInBackground
        @Preference<Bool>("started_by_user", defaultValue: false) public static var startedByUser
    #endif

    #if os(iOS)
        @Preference<Bool>("network_permission_requested", defaultValue: false) public static var networkPermissionRequested
    #endif

    @Preference<Bool>("system_proxy_enabled", defaultValue: true) public static var systemProxyEnabled
}
