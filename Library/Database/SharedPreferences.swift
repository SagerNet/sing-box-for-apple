import Foundation

public enum SharedPreferences {
    public static let selectedProfileID = Preference<Int64>("selected_profile_id", defaultValue: -1)

    #if os(macOS)
        private static let ignoreMemoryLimitByDefault = true
    #else
        private static let ignoreMemoryLimitByDefault = false
    #endif

    public static let ignoreMemoryLimit = Preference<Bool>("ignore_memory_limit", defaultValue: ignoreMemoryLimitByDefault)

    #if os(iOS)
        public static let excludeLocalNetworksByDefault = true
    #elseif os(macOS)
        public static let excludeLocalNetworksByDefault = false
    #endif

    #if !os(tvOS)
        public static let includeAllNetworks = Preference<Bool>("include_all_networks", defaultValue: false)
        public static let excludeAPNs = Preference<Bool>("exclude_apns", defaultValue: true)
        public static let excludeLocalNetworks = Preference<Bool>("exclude_local_networks", defaultValue: excludeLocalNetworksByDefault)
        public static let excludeCellularServices = Preference<Bool>("exclude_cellular_services", defaultValue: true)
        public static let enforceRoutes = Preference<Bool>("enforce_routes", defaultValue: false)

    #endif

    public static func resetPacketTunnel() async {
        #if !os(tvOS)
            let names = [
                ignoreMemoryLimit.name,
                includeAllNetworks.name,
                excludeAPNs.name,
                excludeLocalNetworks.name,
                excludeCellularServices.name,
                enforceRoutes.name,
            ]
        #else
            let names = [ignoreMemoryLimit.name]
        #endif
        try? await batchDelete(names)
    }

    public static let maxLogLines = Preference<Int>("max_log_lines", defaultValue: 300)

    #if os(macOS)
        public static let showMenuBarExtra = Preference<Bool>("show_menu_bar_extra", defaultValue: true)
        public static let menuBarExtraInBackground = Preference<Bool>("menu_bar_extra_in_background", defaultValue: false)
        public static let startedByUser = Preference<Bool>("started_by_user", defaultValue: false)

        public static func resetMacOS() async {
            try? await batchDelete([showMenuBarExtra.name, menuBarExtraInBackground.name])
        }
    #endif

    #if os(iOS)
        public static let networkPermissionRequested = Preference<Bool>("network_permission_requested", defaultValue: false)
    #endif

    public static let systemProxyEnabled = Preference<Bool>("system_proxy_enabled", defaultValue: true)

    #if os(tvOS)
        public static let commandServerPort = Preference<Int32>("command_server_port", defaultValue: 0)
        public static let commandServerSecret = Preference<String>("command_server_secret", defaultValue: "")
    #endif

    // Profile Override

    public static let excludeDefaultRoute = Preference<Bool>("exclude_default_route", defaultValue: false)
    public static let autoRouteUseSubRangesByDefault = Preference<Bool>("auto_route_use_sub_ranges_by_default", defaultValue: false)
    public static let excludeAPNsRoute = Preference<Bool>("exclude_apple_push_notification_services", defaultValue: false)

    public static func resetProfileOverride() async {
        try? await batchDelete([excludeDefaultRoute.name, autoRouteUseSubRangesByDefault.name, excludeAPNsRoute.name])
    }

    // Connections Filter

    public static let connectionStateFilter = Preference<Int>("connection_state_filter", defaultValue: 0)
    public static let connectionSort = Preference<Int>("connection_sort", defaultValue: 0)

    // On Demand Rules

    public static let alwaysOn = Preference<Bool>("always_on", defaultValue: false)

    public static func resetOnDemandRules() async {
        try? await batchDelete([alwaysOn.name])
    }

    // Core

    public static let disableDeprecatedWarnings = Preference<Bool>("disable_deprecated_warnings", defaultValue: false)

    // Dashboard

    public static let enabledDashboardCards = Preference<[String]>("enabled_dashboard_cards", defaultValue: [])
    public static let dashboardCardOrder = Preference<[String]>("dashboard_card_order", defaultValue: [])

    #if DEBUG
        public static let inDebug = true
    #else
        public static let inDebug = false
    #endif
}
