import Libbox
import Library
import SwiftUI

public struct ConnectionsCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: "Connections", isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                if ApplicationLibrary.inPreview {
                    DashboardCardLine(String(localized: "Inbound"), "34")
                    DashboardCardLine(String(localized: "Outbound"), "28")
                } else if let message = commandClient.status {
                    DashboardCardLine(String(localized: "Inbound"), "\(message.connectionsIn)")
                    DashboardCardLine(String(localized: "Outbound"), "\(message.connectionsOut)")
                } else {
                    DashboardCardLine(String(localized: "Inbound"), "...")
                    DashboardCardLine(String(localized: "Outbound"), "...")
                }
            }
        }
    }
}
