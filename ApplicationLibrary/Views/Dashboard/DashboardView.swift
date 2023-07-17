import SwiftUI

public struct DashboardView: View {
    @Environment(\.extensionProfile) private var extensionProfile

    public init() {}

    public var body: some View {
        viewBuilder {
            if let profile = extensionProfile.wrappedValue {
                ActiveDashboardView().environmentObject(profile)
            } else {
                FormView {
                    InstallProfileButton()
                }
            }
        }.navigationTitle("Dashboard")
    }
}
