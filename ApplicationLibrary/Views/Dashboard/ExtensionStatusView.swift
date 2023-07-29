import Libbox
import Library
import SwiftUI

public struct ExtensionStatusView: View {
    @State private var commandClient: LibboxCommandClient?
    @State private var message: LibboxStatusMessage?
    @State private var connectTask: Task<Void, Error>?
    @State private var columnCount: Int = 4
    @State private var alert: Alert?

    private let infoFont = Font.system(.caption, design: .monospaced)

    public init() {}

    public var body: some View {
        viewBuilder {
            VStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columnCount), alignment: .leading) {
                    if ApplicationLibrary.inPreview {
                        StatusItem("Memory", "6.4 MiB")
                        StatusItem("Goroutines", "89")
                        StatusItem("Inbound Connections", "34")
                        StatusItem("Outbound Connections", "28")
                        StatusItem("Uplink", "38 B/s")
                        StatusItem("Downlink", "249 MiB/s")
                        StatusItem("Uplink Total", "52 MiB")
                        StatusItem("Downlink Total", "5.6 GiB")
                    } else if let message {
                        StatusItem("Memory", LibboxFormatBytes(message.memory))
                        StatusItem("Goroutines", "\(message.goroutines)")
                        if message.trafficAvailable {
                            StatusItem("Inbound Connections", "\(message.connectionsIn)")
                            StatusItem("Outbound Connections", "\(message.connectionsOut)")
                            StatusItem("Uplink", LibboxFormatBytes(message.uplink) + "/s")
                            StatusItem("Downlink", LibboxFormatBytes(message.downlink) + "/s")
                            StatusItem("Uplink Total", LibboxFormatBytes(message.uplinkTotal))
                            StatusItem("Downlink Total", LibboxFormatBytes(message.downlinkTotal))
                        }
                    } else {
                        StatusItem("Memory", "Loading...")
                        StatusItem("Goroutines", "Loading...")
                    }
                }.background {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .frame(height: 1)
                            .onChangeCompat(of: geometry.size.width) { newValue in
                                updateColumnCount(newValue)
                            }
                            .onAppear {
                                updateColumnCount(geometry.size.width)
                            }
                    }.padding()
                }
            }
            .frame(alignment: .topLeading)
            .padding([.top, .leading, .trailing])
        }
        .onAppear(perform: doReload)
        .onDisappear {
            connectTask?.cancel()
            if let commandClient {
                try? commandClient.disconnect()
            }
            commandClient = nil
        }
        .alertBinding($alert)
    }

    private func doReload() {
        connectTask?.cancel()
        connectTask = Task.detached {
            await connect()
        }
    }

    private func connect() async {
        let clientOptions = LibboxCommandClientOptions()
        clientOptions.command = LibboxCommandStatus
        clientOptions.statusInterval = Int64(2 * NSEC_PER_SEC)
        let client = LibboxNewCommandClient(FilePath.sharedDirectory.relativePath, statusHandler(self), clientOptions)!

        do {
            for i in 0 ..< 10 {
                try await Task.sleep(nanoseconds: UInt64(Double(100 + (i * 50)) * Double(NSEC_PER_MSEC)))
                try Task.checkCancellation()
                let isConnected: Bool
                do {
                    try client.connect()
                    isConnected = true
                } catch {
                    isConnected = false
                }
                try Task.checkCancellation()
                if isConnected {
                    commandClient = client
                    return
                }
            }
        } catch {
            NSLog("failed to connect status: \(error.localizedDescription)")
            try? client.disconnect()
        }
    }

    private func updateColumnCount(_ width: Double) {
        let v = Int(Int(width) / 155)
        let new = v < 1 ? 1 : (v > 4 ? 4 : (v % 2 == 0 ? v : v - 1))

        if new != columnCount {
            columnCount = new
        }
    }

    private func closeConnections() {
        do {
            try LibboxNewStandaloneCommandClient()!.closeConnections()
        } catch {
            alert = Alert(error)
        }
    }

    private class statusHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private let statusView: ExtensionStatusView

        init(_ statusView: ExtensionStatusView) {
            self.statusView = statusView
        }

        func connected() {}

        func disconnected(_: String?) {}

        func writeLog(_: String?) {}

        func writeStatus(_ message: LibboxStatusMessage?) {
            statusView.message = message
        }

        func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
    }

    private struct StatusItem: View {
        private let name: String
        private let value: String
        init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 16))
            }
            .frame(minWidth: 125)
            #if os(tvOS)
                .padding(EdgeInsets(top: 20, leading: 26, bottom: 20, trailing: 26))
            #else
                .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
            #endif
                .background(backgroundColor)
                .cornerRadius(10)
        }

        private var backgroundColor: Color {
            #if os(iOS)
                return Color(uiColor: .secondarySystemGroupedBackground)
            #elseif os(macOS)
                return Color(nsColor: .textBackgroundColor)
            #elseif os(tvOS)
                return Color(uiColor: .black)
            #endif
        }
    }
}
