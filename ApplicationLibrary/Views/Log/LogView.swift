import Library
import SwiftUI
#if !os(tvOS)
    import UniformTypeIdentifiers
    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif
#endif

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
            } else if viewModel.visibleLogs.isEmpty {
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
        .alertBinding($viewModel.alert)
        .background(
            LogExportView(
                showFileExporter: $viewModel.showFileExporter,
                logFileURL: $viewModel.logFileURL,
                alert: $viewModel.alert,
                cleanup: viewModel.cleanupLogFile
            )
        )
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
            let previewLogs = logList.map { message in
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
                        ForEach(viewModel.visibleLogs) { logEntry in
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
                .onChangeCompat(of: viewModel.visibleLogs.count) { _ in
                    if !viewModel.isPaused {
                        scrollToLastEntry(reader)
                    }
                }
            }
        #else
            LogTextView(
                logs: viewModel.visibleLogs,
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
            guard let lastEntry = viewModel.visibleLogs.last else { return }
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
            #if !os(tvOS)
                Menu {
                    Button(action: viewModel.copyToClipboard) {
                        Label("To Clipboard", systemImage: "doc.on.clipboard")
                    }
                    Button(action: {
                        viewModel.prepareLogFile()
                        viewModel.showFileExporter = true
                    }, label: {
                        Label("To File", systemImage: "arrow.down.doc")
                    })
                    Button(action: viewModel.prepareLogFile) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            #endif
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

    private struct LogExportView: View {
        @Binding var showFileExporter: Bool
        @Binding var logFileURL: URL?
        @Binding var alert: Alert?
        @State private var showShareSheet = false
        let cleanup: () -> Void

        var body: some View {
            Color.clear
                .fileExporter(
                    isPresented: $showFileExporter,
                    document: logFileURL.map { LogTextDocument(url: $0) },
                    contentType: .plainText,
                    defaultFilename: "logs.txt"
                ) { result in
                    cleanup()
                    logFileURL = nil
                    if case let .failure(error) = result {
                        alert = Alert(error)
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    if let url = logFileURL {
                        #if os(iOS)
                            ShareViewController(activityItems: [url])
                        #elseif os(macOS)
                            ShareView(items: [url], alert: $alert)
                        #endif
                    }
                }
                .onChange(of: logFileURL) { newValue in
                    if newValue != nil, !showFileExporter {
                        showShareSheet = true
                    }
                }
                .onChange(of: showShareSheet) { newValue in
                    if !newValue {
                        cleanup()
                        logFileURL = nil
                    }
                }
        }
    }

    private struct LogTextDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText] }

        private let url: URL

        init(url: URL) {
            self.url = url
        }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: tempURL)
            url = tempURL
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            try FileWrapper(url: url)
        }
    }

    #if os(iOS)
        private struct ShareViewController: UIViewControllerRepresentable {
            let activityItems: [Any]

            func makeUIViewController(context _: Context) -> UIActivityViewController {
                UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            }

            func updateUIViewController(_: UIActivityViewController, context _: Context) {}
        }

    #elseif os(macOS)
        private struct ShareView: NSViewRepresentable {
            let items: [Any]
            @Binding var alert: Alert?

            func makeNSView(context _: Context) -> NSView {
                let view = NSView()
                return view
            }

            func updateNSView(_ nsView: NSView, context _: Context) {
                let picker = NSSharingServicePicker(items: items)
                DispatchQueue.main.async {
                    picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                }
            }
        }
    #endif
#endif
