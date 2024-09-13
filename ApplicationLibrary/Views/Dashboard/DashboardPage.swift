import Foundation
import Library
import SwiftUI

public enum DashboardPage: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case overview
    case groups
    case connections
}

public extension DashboardPage {
    static func enabledCases() -> [DashboardPage] {
        var cases: [DashboardPage] = [
            .overview,
            .groups,
        ]
        #if !tvOS
            if Variant.isBeta {
                cases.append(.connections)
            }
        #endif
        return cases
    }
}

public extension DashboardPage {
    var title: String {
        switch self {
        case .overview:
            return NSLocalizedString("Overview", comment: "")
        case .groups:
            return NSLocalizedString("Groups", comment: "")
        case .connections:
            return NSLocalizedString("Connections", comment: "")
        }
    }

    var label: some View {
        switch self {
        case .overview:
            return Label(title, systemImage: "text.and.command.macwindow")
        case .groups:
            return Label(title, systemImage: "rectangle.3.group.fill")
        case .connections:
            return Label(title, systemImage: "list.bullet.rectangle.portrait.fill")
        }
    }

    @MainActor
    func contentView(_ profileList: Binding<[ProfilePreview]>, _ selectedProfileID: Binding<Int64>, _ systemProxyAvailable: Binding<Bool>, _ systemProxyEnabled: Binding<Bool>) -> some View {
        viewBuilder {
            switch self {
            case .overview:
                OverviewView(profileList, selectedProfileID, systemProxyAvailable, systemProxyEnabled)
            case .groups:
                GroupListView()
            case .connections:
                ConnectionListView()
            }
        }
    }
}
