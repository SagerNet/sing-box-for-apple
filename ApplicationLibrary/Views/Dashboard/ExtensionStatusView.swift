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
                        StatusItem("Status") {
                            StatusLine("Memory", "6.4 MiB")
                            StatusLine("Goroutines", "89")
                        }
                        StatusItem("Connections") {
                            StatusLine("Inbound", "34")
                            StatusLine("Outbound", "28")
                        }
                        StatusItem("Traffic") {
                            StatusLine("Uplink", "38 B/s")
                            StatusLine("Downlink", "249 MiB/s")
                        }
                        StatusItem("TrafficTotal") {
                            StatusLine("Uplink", "52 MiB")
                            StatusLine("Downlink", "5.6 GiB")
                        }
                    } else if let message {
                        StatusItem("Status") {
                            StatusLine("Memory", LibboxFormatBytes(message.memory))
                            StatusLine("Goroutines", "\(message.goroutines)")
                        }
                        StatusItem("Connections") {
                            StatusLine("Inbound", "\(message.connectionsIn)")
                            StatusLine("Outbound", "\(message.connectionsOut)")
                        }
                        if message.trafficAvailable {
                            StatusItem("Traffic") {
                                StatusLine("Uplink", "\(LibboxFormatBytes(message.uplink))/s")
                                StatusLine("Downlink", "\(LibboxFormatBytes(message.downlink))/s")
                            }
                            StatusItem("Traffic Total") {
                                StatusLine("Uplink", LibboxFormatBytes(message.uplinkTotal))
                                StatusLine("Downlink", LibboxFormatBytes(message.downlinkTotal))
                            }
                        }
                    } else {
                        StatusItem("Status") {
                            StatusLine("Memory", "...")
                            StatusLine("Goroutines", "...")
                        }
                        StatusItem("Connections") {
                            StatusLine("Inbound", "...")
                            StatusLine("Outbound", "...")
                        }
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

    private struct StatusItem<T>: View where T: View {
        private let title: String
        @ViewBuilder private let content: () -> T

        init(_ title: String, @ViewBuilder content: @escaping () -> T) {
            self.title = title
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                }.padding(.bottom, 8)
                content()
            }
            .frame(minWidth: 125, alignment: .topLeading)
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

    private struct StatusLine: View {
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
}
