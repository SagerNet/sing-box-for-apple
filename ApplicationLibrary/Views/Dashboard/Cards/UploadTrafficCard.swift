import Libbox
import Library
import SwiftUI

public struct UploadTrafficCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: "", isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                DashboardCardHeader(icon: "arrow.up.circle.fill", title: "Upload")

                if ApplicationLibrary.inPreview {
                    Text("38 B/s")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("52 MB")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let message = commandClient.status, message.trafficAvailable {
                    Text("\(LibboxFormatBytes(message.uplink))/s")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text(LibboxFormatBytes(message.uplinkTotal))
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
                    data: commandClient.uplinkHistory,
                    lineColor: .primary
                )
            }
        }
    }
}
