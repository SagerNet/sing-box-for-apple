import Library
import SwiftUI

public struct LogView: View {
    @Environment(\.selection) private var selection
    @EnvironmentObject private var environments: ExtensionEnvironments

    public init() {}

    public var body: some View {
        LogView0().environmentObject(environments.logClient)
    }

    private struct LogView0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var logClient: CommandClient
        private let logFont = Font.system(.caption2, design: .monospaced)

        var body: some View {
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logList.enumerated()), id: \.offset) { it in
                            Text(it.element)
                                .font(logFont)
                            #if os(tvOS)
                                .focusable()
                            #endif
                            Spacer(minLength: 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                }
                #if os(tvOS)
                .focusEffectDisabled()
                .focusSection()
                #endif
            } else if logClient.logList.isEmpty {
                VStack {
                    if logClient.isConnected {
                        Text("Empty logs")
                    } else {
                        Text("Service not started").onAppear {
                            environments.connectLog()
                        }
                    }
                }
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading, spacing: 0) {
                            ForEach(Array(logClient.logList.enumerated()), id: \.offset) { it in
                                Text(it.element)
                                    .font(logFont)
                                #if os(tvOS)
                                    .focusable()
                                #endif
                                Spacer(minLength: 8)
                            }

                            .onChangeCompat(of: logClient.logList.count) { newCount in
                                withAnimation {
                                    reader.scrollTo(newCount - 1)
                                }
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
                        reader.scrollTo(logClient.logList.count - 1)
                    }
                }
            }
        }
    }
}
