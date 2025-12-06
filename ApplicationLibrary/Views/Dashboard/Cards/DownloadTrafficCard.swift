import Libbox
import Library
import SwiftUI

public struct DownloadTrafficCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: "", isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                DashboardCardHeader(icon: "arrow.down.circle.fill", title: "Download")

                if ApplicationLibrary.inPreview {
                    Text("249 MB/s")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("5.6 GB")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let message = commandClient.status, message.trafficAvailable {
                    Text("\(LibboxFormatBytes(message.downlink))/s")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text(LibboxFormatBytes(message.downlinkTotal))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("...")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TrafficLineChart(
                    data: commandClient.downlinkHistory,
                    lineColor: .primary
                )
            }
        }
    }
}
