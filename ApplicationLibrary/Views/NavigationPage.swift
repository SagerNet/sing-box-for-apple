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
            return NSLocalizedString("Dashboard", comment: "")
        #if os(macOS)
            case .groups:
                return NSLocalizedString("Groups", comment: "")
        #endif
        case .logs:
            return NSLocalizedString("Logs", comment: "")
        case .profiles:
            return NSLocalizedString("Profiles", comment: "")
        case .settings:
            return NSLocalizedString("Settings", comment: "")
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
