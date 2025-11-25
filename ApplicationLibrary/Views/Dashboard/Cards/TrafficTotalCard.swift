import Libbox
import Library
import SwiftUI

public struct TrafficTotalCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: String(localized: "Traffic Total"), isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                if ApplicationLibrary.inPreview {
                    DashboardCardLine(String(localized: "Uplink"), "52 MB")
                    DashboardCardLine(String(localized: "Downlink"), "5.6 GB")
                } else if let message = commandClient.status, message.trafficAvailable {
                    DashboardCardLine(String(localized: "Uplink"), LibboxFormatBytes(message.uplinkTotal))
                    DashboardCardLine(String(localized: "Downlink"), LibboxFormatBytes(message.downlinkTotal))
                } else {
                    DashboardCardLine(String(localized: "Uplink"), "...")
                    DashboardCardLine(String(localized: "Downlink"), "...")
                }
            }
        }
    }
}
