import Libbox
import Library
import SwiftUI

public struct StatusCard: View {
    @EnvironmentObject private var commandClient: CommandClient

    public init() {}

    public var body: some View {
        DashboardCardView(title: String(localized: "Status"), isHalfWidth: true) {
            VStack(alignment: .leading, spacing: 8) {
                if ApplicationLibrary.inPreview {
                    DashboardCardLine(String(localized: "Memory"), "6.4 MB")
                    DashboardCardLine(String(localized: "Goroutines"), "89")
                } else if let message = commandClient.status {
                    DashboardCardLine(String(localized: "Memory"), LibboxFormatMemoryBytes(message.memory))
                    DashboardCardLine(String(localized: "Goroutines"), "\(message.goroutines)")
                } else {
                    DashboardCardLine(String(localized: "Memory"), "...")
                    DashboardCardLine(String(localized: "Goroutines"), "...")
                }
            }
        }
    }
}
