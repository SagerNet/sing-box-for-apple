import Libbox
import Library
import SwiftUI

public struct TrafficCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: "Traffic", isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                if ApplicationLibrary.inPreview {
                    CardLine(String(localized: "Uplink"), "38 B/s")
                    CardLine(String(localized: "Downlink"), "249 MB/s")
                } else if let message = commandClient.status, message.trafficAvailable {
                    CardLine(String(localized: "Uplink"), "\(LibboxFormatBytes(message.uplink))/s")
                    CardLine(String(localized: "Downlink"), "\(LibboxFormatBytes(message.downlink))/s")
                } else {
                    CardLine(String(localized: "Uplink"), "...")
                    CardLine(String(localized: "Downlink"), "...")
                }
            }
        }
    }
}

private struct CardLine: View {
    private let name: String
    private let value: String

    init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }

    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}
