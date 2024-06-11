import Foundation
import Library
import SwiftUI

public enum NavigationPage: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case dashboard
    #if os(macOS)
        case groups
    #endif
    case logs
    case profiles
    case settings
}

public extension NavigationPage {
    #if os(macOS)
        static var macosDefaultPages: [NavigationPage] {
            [.logs, .profiles, .settings]
        }
    #endif

    var label: some View {
        Label(title, systemImage: iconImage)
            .tint(.textColor)
    }

    var title: String {
        switch self {
        case .dashboard:
            return String(localized: "Dashboard")
        #if os(macOS)
            case .groups:
                return String(localized: "Groups")
        #endif
        case .logs:
            return String(localized: "Logs")
        case .profiles:
            return String(localized: "Profiles")
        case .settings:
            return String(localized: "Settings")
        }
    }

    private var iconImage: String {
        switch self {
        case .dashboard:
            return "text.and.command.macwindow"
        #if os(macOS)
            case .groups:
                return "rectangle.3.group.fill"
        #endif
        case .logs:
            return "doc.text.fill"
        case .profiles:
            return "list.bullet.rectangle.fill"
        case .settings:
            return "gear.circle.fill"
        }
    }

    @MainActor
    var contentView: some View {
        viewBuilder {
            switch self {
            case .dashboard:
                DashboardView()
            #if os(macOS)
                case .groups:
                    GroupListView()
            #endif
            case .logs:
                LogView()
            case .profiles:
                ProfileView()
            case .settings:
                SettingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        #if os(iOS)
            .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }

    #if os(macOS)
        func visible(_ profile: ExtensionProfile?) -> Bool {
            switch self {
            case .groups:
                return profile?.status.isConnectedStrict == true
            default:
                return true
            }
        }
    #endif
}
