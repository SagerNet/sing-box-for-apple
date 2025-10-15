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
                emptyContent
            } else if viewModel.filteredLogs.isEmpty {
                emptyContent
            } else {
                logScrollView
            }
        }
        #if !os(tvOS)
        .applySearchable(text: $viewModel.searchText, isSearching: $viewModel.isSearching, shouldShow: viewModel.isSearching)
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
        #if os(tvOS)
            return ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(logList.indices, id: \.self) { index in
                        Text(ANSIColors.parseAnsiString(logList[index]))
                            .font(logFont)
                            .focusable()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            }
            .focusEffectDisabled()
            .focusSection()
        #else
            let previewLogs = logList.enumerated().map { _, message in
                LogEntry(level: 4, message: message)
            }
            return LogTextView(
                logs: previewLogs,
                font: logFont,
                shouldAutoScroll: false,
                searchText: ""
            )
        #endif
    }

    @ViewBuilder
    private var emptyContent: some View {
        if viewModel.isConnected {
            Text("Empty logs")
        } else {
            Text("Service not started").onAppear {
                environments.connect()
            }
        }
    }

    private var logScrollView: some View {
        #if os(tvOS)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.filteredLogs) { logEntry in
                            Text(highlightedText(for: logEntry.message))
                                .font(logFont)
                                .focusable()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                }
                .focusEffectDisabled()
                .focusSection()
                .onAppear {
                    scrollToLastEntry(reader)
                }
                .onChangeCompat(of: viewModel.filteredLogs.count) { _ in
                    if !viewModel.isPaused {
                        scrollToLastEntry(reader)
                    }
                }
            }
        #else
            LogTextView(
                logs: viewModel.filteredLogs,
                font: logFont,
                shouldAutoScroll: !viewModel.isPaused,
                searchText: viewModel.searchText
            )
        #endif
    }

    #if os(tvOS)
        private func highlightedText(for message: String) -> AttributedString {
            var attributedString = ANSIColors.parseAnsiString(message)

            if !viewModel.searchText.isEmpty {
                let searchText = viewModel.searchText
                let messageString = String(attributedString.characters)
                var searchRange = messageString.startIndex ..< messageString.endIndex

                while let range = messageString.range(of: searchText, range: searchRange) {
                    if let attributedRange = Range<AttributedString.Index>(range, in: attributedString) {
                        attributedString[attributedRange].backgroundColor = .yellow
                    }
                    searchRange = range.upperBound ..< messageString.endIndex
                }
            }

            return attributedString
        }
    #endif

    #if os(tvOS)
        private func scrollToLastEntry(_ reader: ScrollViewProxy) {
            guard let lastEntry = viewModel.filteredLogs.last else { return }
            withAnimation {
                reader.scrollTo(lastEntry.id, anchor: .bottom)
            }
        }
    #endif

    @ViewBuilder
    private var toolbarButtons: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            Button(action: viewModel.toggleSearch) {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
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

#if !os(tvOS)
    private extension View {
        func applySearchable(text: Binding<String>, isSearching: Binding<Bool>, shouldShow: Bool) -> some View {
            if #available(iOS 17.0, macOS 14.0, *) {
                if shouldShow {
                    return AnyView(searchable(text: text, isPresented: isSearching))
                } else {
                    return AnyView(self)
                }
            } else {
                return AnyView(searchable(text: text))
            }
        }
    }
#endif
