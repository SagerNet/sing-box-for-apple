import Libbox
import Library
import SwiftUI

public struct ExtensionStatusView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var commandClient = CommandClient(.status)

    @State private var columnCount: Int = 4
    @State private var alert: Alert?

    private let infoFont = Font.system(.caption, design: .monospaced)

    public init() {}
    public var body: some View {
        if columnCount == 1 {
            ScrollView {
                body0
            }
        } else {
            body0
        }
    }

    public var body0: some View {
        viewBuilder {
            VStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columnCount), alignment: .leading) {
                    if ApplicationLibrary.inPreview {
                        StatusItem("Status") {
                            StatusLine("Memory", "6.4 MB")
                            StatusLine("Goroutines", "89")
                        }
                        StatusItem("Connections") {
                            StatusLine("Inbound", "34")
                            StatusLine("Outbound", "28")
                        }
                        StatusItem("Traffic") {
                            StatusLine("Uplink", "38 B/s")
                            StatusLine("Downlink", "249 MB/s")
                        }
                        StatusItem("TrafficTotal") {
                            StatusLine("Uplink", "52 MB")
                            StatusLine("Downlink", "5.6 GB")
                        }
                    } else if let message = commandClient.status {
                        StatusItem("Status") {
                            StatusLine("Memory", LibboxFormatMemoryBytes(message.memory))
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
        .onAppear {
            commandClient.connect { urlString in
                openURL(URL(string: urlString)!)
            }
        }
        .onDisappear {
            commandClient.disconnect()
        }
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                commandClient.connect()
            } else {
                commandClient.disconnect()
            }
        }
        .alertBinding($alert)
    }

    private func updateColumnCount(_ width: Double) {
        let v = Int(Int(width) / 155)
        let new = v <= 1 ? 1 : (v > 4 ? 4 : (v % 2 == 0 ? v : v - 1))

        if new != columnCount {
            columnCount = new
        }
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
