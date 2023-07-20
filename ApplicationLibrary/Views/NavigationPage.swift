import Foundation
import Library
import SwiftUI

public enum NavigationPage: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case dashboard
    case groups
    case logs
    case profiles
    case settings
}

public extension NavigationPage {
    var label: some View {
        Label(title, systemImage: iconImage)
    }

    var title: String {
        switch self {
        case .dashboard:
            return NSLocalizedString("Dashboard", comment: "")
        case .groups:
            return NSLocalizedString("Groups", comment: "")
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
        case .groups:
            return "rectangle.3.group.fill"
        case .logs:
            return "doc.text.fill"
        case .profiles:
            return "list.bullet.rectangle.fill"
        case .settings:
            return "gear.circle.fill"
        }
    }

    var contentView: some View {
        viewBuilder {
            switch self {
            case .dashboard:
                DashboardView()
            case .groups:
                GroupListView()
            case .logs:
                LogView()
            case .profiles:
                ProfileView()
            case .settings:
                SettingView()
            }
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }

    func visible(_ profile: ExtensionProfile?) -> Bool {
        if ApplicationLibrary.inPreview {
            return true
        }
        switch self {
        case .groups:
            return profile?.status.isConnectedStrict == true
        default:
            return true
        }
    }
}
