import Libbox
import Library
import SwiftUI

public struct TrafficCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: String(localized: "Traffic"), isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                if ApplicationLibrary.inPreview {
                    DashboardCardLine(String(localized: "Uplink"), "38 B/s")
                    DashboardCardLine(String(localized: "Downlink"), "249 MB/s")
                } else if let message = commandClient.status, message.trafficAvailable {
                    DashboardCardLine(String(localized: "Uplink"), "\(LibboxFormatBytes(message.uplink))/s")
                    DashboardCardLine(String(localized: "Downlink"), "\(LibboxFormatBytes(message.downlink))/s")
                } else {
                    DashboardCardLine(String(localized: "Uplink"), "...")
                    DashboardCardLine(String(localized: "Downlink"), "...")
                }
            }
        }
    }
}
