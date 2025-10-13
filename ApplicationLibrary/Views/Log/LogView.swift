import Library
import SwiftUI

public struct LogView: View {
    @Environment(\.selection) private var selection
    @EnvironmentObject private var environments: ExtensionEnvironments

    public init() {}

    public var body: some View {
        LogView0().environmentObject(environments.commandClient)
    }

    private struct LogView0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var commandClient: CommandClient
        @State private var selectedLogLevel: Int?
        private let logFont = Font.system(.caption2, design: .monospaced)

        private var filteredLogList: [LogEntry] {
            let effectiveLevel = selectedLogLevel ?? commandClient.defaultLogLevel
            return commandClient.logList.filter { $0.level <= effectiveLevel }
        }

        var body: some View {
            Group {
                if ApplicationLibrary.inPreview {
                    let logList = [
                        "(packet-tunnel) log server started",
                        "INFO[0000] router: loaded geoip database: 250 codes",
                        "INFO[0000] router: loaded geosite database: 1400 codes",
                        "INFO[0000] router: updated default interface en0, index 11",
                        "inbound/tun[0]: started at utun3",
                        "sing-box started (1.666s)",
                    ]
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(logList.indices, id: \.self) { index in
                                Text(ANSIColors.parseAnsiString(logList[index]))
                                    .font(logFont)
                                #if os(tvOS)
                                    .focusable()
                                #endif
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding()
                    }
                    #if os(tvOS)
                    .focusEffectDisabled()
                    .focusSection()
                    #endif
                } else if commandClient.logList.isEmpty {
                    VStack {
                        if commandClient.isConnected {
                            Text("Empty logs")
                        } else {
                            Text("Service not started").onAppear {
                                environments.connect()
                            }
                        }
                    }
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredLogList) { logEntry in
                                    Text(ANSIColors.parseAnsiString(logEntry.message))
                                        .font(logFont)
                                    #if os(tvOS)
                                        .focusable()
                                    #endif
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding()
                        }
                        #if os(tvOS)
                        .focusEffectDisabled()
                        .focusSection()
                        #endif
                        .onAppear {
                            if let lastEntry = filteredLogList.last {
                                reader.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                        .onChangeCompat(of: filteredLogList.count) { _ in
                            guard let lastEntry = filteredLogList.last else {
                                return
                            }
                            withAnimation {
                                reader.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            #if !os(tvOS)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("Log Level", selection: $selectedLogLevel) {
                            Text(NSLocalizedString("Default", comment: "Log level filter default option")).tag(Int?.none)
                            ForEach(LogLevel.allCases) { level in
                                Text(level.name).tag(Int?.some(level.rawValue))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.circle")
                    }
                }
            }
            #endif
        }
    }
}
