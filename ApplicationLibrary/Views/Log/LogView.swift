import SwiftUI

public struct LogView: View {
    @Environment(\.logClient) private var logClient

    public init() {}

    public var body: some View {
        viewBuilder {
            if let logClient = logClient.wrappedValue {
                LogView0().environmentObject(logClient)
            } else {
                Text("Service not started")
            }
        }
        .navigationTitle("Logs")
    }

    private struct LogView0: View {
        @Environment(\.selection) private var selection
        @Environment(\.extensionProfile) private var extensionProfile
        @EnvironmentObject private var logClient: LogClient

        private let logFont = Font.system(.caption2, design: .monospaced)

        var body: some View {
            viewBuilder {
                if logClient.logList.isEmpty {
                    VStack {
                        if logClient.isConnected {
                            Text("Empty logs")
                        } else {
                            Text("Service not started").onAppear(perform: connectLog)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(logClient.logList.enumerated()), id: \.offset) { it in
                                    Text(it.element)
                                        .font(logFont)
                                    #if os(tvOS)
                                        .focusable()
                                    #endif
                                    Spacer(minLength: 5)
                                }

                                .onChange(of: logClient.logList.count) { newCount in
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

        private func connectLog() {
            if ApplicationLibrary.inPreview {
                logClient.reconnect()
            } else {
                guard let profile = extensionProfile.wrappedValue else {
                    return
                }
                if profile.status.isConnected, !logClient.isConnected {
                    logClient.reconnect()
                }
            }
        }
    }
}
