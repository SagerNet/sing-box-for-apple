import Libbox
import SwiftUI

@MainActor
public struct ConnectionView: View {
    private let connection: Connection
    public init(_ connection: Connection) {
        self.connection = connection
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    public func formatInterval(_ createdAt: Date, _ closedAt: Date) -> String {
        LibboxFormatDuration(Int64((closedAt.timeIntervalSince1970 - createdAt.timeIntervalSince1970) * 1000))
    }

    @State private var alert: Alert?

    public var body: some View {
        FormNavigationLink {
            ConnectionDetailsView(connection)
        } label: {
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(alignment: .center) {
                            Text("\(connection.network.uppercased()) \(connection.displayDestination)")
                            Spacer()
                            if connection.closedAt == nil {
                                Text("Active").foregroundStyle(.green)
                            } else {
                                Text("Closed").foregroundStyle(.red)
                            }
                        }
                        .font(.caption2.monospaced().bold())
                        .padding([.bottom], 4)
                        HStack {
                            if let closedAt = connection.closedAt {
                                VStack(alignment: .leading) {
                                    Text("↑ \(LibboxFormatBytes(connection.uploadTotal))")
                                    Text("↓ \(LibboxFormatBytes(connection.downloadTotal))")
                                }
                                .font(.caption2)
                                VStack(alignment: .leading) {
                                    Text(format(connection.createdAt))
                                    Text(formatInterval(connection.createdAt, closedAt))
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(connection.inboundType + "/" + connection.inbound)
                                    Text(connection.chain.reversed().joined(separator: "/"))
                                }
                            } else {
                                VStack(alignment: .leading) {
                                    Text("↑ \(LibboxFormatBytes(connection.upload))/s")
                                    Text("↓ \(LibboxFormatBytes(connection.download))/s")
                                }
                                .font(.caption2)
                                VStack(alignment: .leading) {
                                    Text(LibboxFormatBytes(connection.uploadTotal))
                                    Text(LibboxFormatBytes(connection.downloadTotal))
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(connection.inboundType + "/" + connection.inbound)
                                    Text(connection.chain.reversed().joined(separator: "/"))
                                }
                            }
                        }
                        .font(.caption2.monospaced())
                    }
                }
                .foregroundColor(.textColor)
                #if !os(tvOS)
                    .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                    .background(backgroundColor)
                    .cornerRadius(10)
                #endif
            }
            .background(.clear)
        }
        #if !os(tvOS)
        .buttonStyle(.borderless)
        #endif
        .alertBinding($alert)
        .contextMenu {
            if connection.closedAt == nil {
                Button("Close", role: .destructive) {
                    Task {
                        await closeConnection()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var backgroundColor: Color {
        #if os(iOS)
            return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
            return Color(nsColor: .textBackgroundColor)
        #elseif os(tvOS)
            return Color.black
        #endif
    }

    private nonisolated func closeConnection() async {
        do {
            try LibboxNewStandaloneCommandClient()!.closeConnection(connection.id)
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
