import SwiftUI

public struct DashboardView: View {
    @Environment(\.extensionProfile) private var extensionProfile

    public init() {}

    public var body: some View {
        FormView {
            if let profile = extensionProfile.wrappedValue {
                ActiveDashboardView().environmentObject(profile)
            } else {
                InstallProfileButton()
            }
        }.navigationTitle("Dashboard")
    }
}
