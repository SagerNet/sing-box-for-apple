import Library
import SwiftUI

public struct LogView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments

    public init() {}

    public var body: some View {
        LogViewContent(commandClient: environments.commandClient)
    }
}

private struct LogViewContent: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel: LogViewModel
    private let logFont = Font.system(.caption2, design: .monospaced)

    init(commandClient: CommandClient) {
        _viewModel = StateObject(wrappedValue: LogViewModel(commandClient: commandClient))
    }

    var body: some View {
        Group {
            if ApplicationLibrary.inPreview {
                previewContent
            } else if viewModel.isEmpty {
                emptyStateContent
            } else if viewModel.filteredLogs.isEmpty {
                emptyLogsContent
            } else {
                logScrollView
            }
        }
        #if !os(tvOS)
        .toolbar {
            ToolbarItemGroup {
                if !viewModel.isEmpty {
                    toolbarButtons
                }
            }
        }
        #endif
    }

    private var previewContent: some View {
        let logList = [
            "(packet-tunnel) log server started",
            "INFO[0000] router: loaded geoip database: 250 codes",
            "INFO[0000] router: loaded geosite database: 1400 codes",
            "INFO[0000] router: updated default interface en0, index 11",
            "inbound/tun[0]: started at utun3",
            "sing-box started (1.666s)",
        ]
        return ScrollView {
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
    }

    private var emptyStateContent: some View {
        VStack {
            if viewModel.isConnected {
                Text("Empty logs")
            } else {
                Text("Service not started").onAppear {
                    environments.connect()
                }
            }
        }
    }

    private var emptyLogsContent: some View {
        Text("Empty logs")
    }

    private var logScrollView: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.filteredLogs) { logEntry in
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
                scrollToLastEntry(reader: reader)
            }
            .onChangeCompat(of: viewModel.filteredLogs.count) { _ in
                if !viewModel.isPaused {
                    scrollToLastEntry(reader: reader)
                }
            }
        }
    }

    private func scrollToLastEntry(reader: ScrollViewProxy) {
        guard let lastEntry = viewModel.filteredLogs.last else { return }
        withAnimation {
            reader.scrollTo(lastEntry.id, anchor: .bottom)
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button(action: viewModel.togglePause) {
            Label(
                viewModel.isPaused ? NSLocalizedString("Resume", comment: "Resume log auto-scroll") : NSLocalizedString("Pause", comment: "Pause log auto-scroll"),
                systemImage: viewModel.isPaused ? "play.circle" : "pause.circle"
            )
        }
        Menu {
            Menu {
                Picker("Log Level", selection: $viewModel.selectedLogLevel) {
                    Text(NSLocalizedString("Default", comment: "Log level filter default option")).tag(Int?.none)
                    ForEach(LogLevel.allCases) { level in
                        Text(level.name).tag(Int?.some(level.rawValue))
                    }
                }
            } label: {
                Label("Log Level", systemImage: "slider.horizontal.3")
            }
            Divider()
            Button(role: .destructive, action: viewModel.clearLogs) {
                Label(NSLocalizedString("Clear Logs", comment: "Clear all logs"), systemImage: "trash")
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.circle")
        }
    }
}
