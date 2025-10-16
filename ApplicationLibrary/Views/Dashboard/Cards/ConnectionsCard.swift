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
                    CardLine(String(localized: "Inbound"), "34")
                    CardLine(String(localized: "Outbound"), "28")
                } else if let message = commandClient.status {
                    CardLine(String(localized: "Inbound"), "\(message.connectionsIn)")
                    CardLine(String(localized: "Outbound"), "\(message.connectionsOut)")
                } else {
                    CardLine(String(localized: "Inbound"), "...")
                    CardLine(String(localized: "Outbound"), "...")
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
