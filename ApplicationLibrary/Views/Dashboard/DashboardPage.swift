import Foundation
import Library
import SwiftUI

public enum DashboardPage: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case overview
    case groups
}

public extension DashboardPage {
    var title: String {
        switch self {
        case .overview:
            return String(localized: "Overview")
        case .groups:
            return String(localized: "Groups")
        }
    }

    var label: some View {
        switch self {
        case .overview:
            return Label("Overview", systemImage: "text.and.command.macwindow")
        case .groups:
            return Label("Groups", systemImage: "rectangle.3.group.fill")
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
            }
        }
    }
}
