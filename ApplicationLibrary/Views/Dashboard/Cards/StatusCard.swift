import Libbox
import Library
import SwiftUI

public struct StatusCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: "Status", isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                if ApplicationLibrary.inPreview {
                    CardLine(String(localized: "Memory"), "6.4 MB")
                    CardLine(String(localized: "Goroutines"), "89")
                } else if let message = commandClient.status {
                    CardLine(String(localized: "Memory"), LibboxFormatMemoryBytes(message.memory))
                    CardLine(String(localized: "Goroutines"), "\(message.goroutines)")
                } else {
                    CardLine(String(localized: "Memory"), "...")
                    CardLine(String(localized: "Goroutines"), "...")
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
