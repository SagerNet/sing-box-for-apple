import Foundation

#if os(macOS)
    public enum MenuBarExtraSpeedMode: Int, CaseIterable {
        case disabled = 0
        case enabled = 1
        case unified = 2

        public var name: String {
            switch self {
            case .disabled:
                return NSLocalizedString("Disabled", comment: "")
            case .enabled:
                return NSLocalizedString("Enabled", comment: "")
            case .unified:
                return NSLocalizedString("Unified", comment: "")
            }
        }
    }
#endif

public enum SharedPreferences {
    public static let selectedProfileID = Preference<Int64>("selected_profile_id", defaultValue: -1)

    #if !os(macOS)
        public static let ignoreMemoryLimit = Preference<Bool>("ignore_memory_limit", defaultValue: false)
    #endif

    #if os(iOS)
        private static let excludeLocalNetworksByDefault = true
    #elseif os(macOS)
        private static let excludeLocalNetworksByDefault = false
    #endif

    #if !os(tvOS)
        public static let includeAllNetworks = Preference<Bool>("include_all_networks", defaultValue: false)
        public static let excludeAPNs = Preference<Bool>("exclude_apns", defaultValue: true)
        public static let excludeLocalNetworks = Preference<Bool>("exclude_local_networks", defaultValue: excludeLocalNetworksByDefault)
        public static let excludeCellularServices = Preference<Bool>("exclude_cellular_services", defaultValue: true)
        public static let enforceRoutes = Preference<Bool>("enforce_routes", defaultValue: false)

    #endif

    public static func resetPacketTunnel() async {
        #if os(macOS)
            let names = [
                includeAllNetworks.name,
                excludeAPNs.name,
                excludeLocalNetworks.name,
                excludeCellularServices.name,
                enforceRoutes.name,
            ]
        #elseif os(tvOS)
            let names = [ignoreMemoryLimit.name]
        #else
            let names = [
                ignoreMemoryLimit.name,
                includeAllNetworks.name,
                excludeAPNs.name,
                excludeLocalNetworks.name,
                excludeCellularServices.name,
                enforceRoutes.name,
            ]
        #endif
        try? await batchDelete(names)
    }

    public static let maxLogLines = Preference<Int>("max_log_lines", defaultValue: 300)

    #if os(macOS)
        public static let showMenuBarExtra = Preference<Bool>("show_menu_bar_extra", defaultValue: true)
        public static let menuBarExtraInBackground = Preference<Bool>("menu_bar_extra_in_background", defaultValue: false)
        public static let menuBarExtraSpeedMode = Preference<Int>("menu_bar_extra_speed_mode_1", defaultValue: MenuBarExtraSpeedMode.enabled.rawValue)
        public static let startedByUser = Preference<Bool>("started_by_user", defaultValue: false)

        public static func resetMacOS() async {
            try? await batchDelete([
                showMenuBarExtra.name,
                menuBarExtraInBackground.name,
                menuBarExtraSpeedMode.name,
            ])
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
    public static let onDemandEnabled = Preference<Bool>("on_demand_enabled", defaultValue: false)
    public static let onDemandRules = Preference<[OnDemandRule]>("on_demand_rules", defaultValue: [])

    public static func resetOnDemandRules() async throws {
        try await batchDelete([alwaysOn.name, onDemandEnabled.name, onDemandRules.name])
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
