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
        LogViewContent(commandClient: environments.commandClient, initialSearchText: environments.logSearchText)
    }
}

private struct LogViewContent: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel: LogViewModel
    #if os(iOS)
        @State private var remoteServers: [RemoteServer] = []
    #endif

    init(commandClient: CommandClient, initialSearchText: String = "") {
        _viewModel = StateObject(wrappedValue: LogViewModel(commandClient: commandClient, searchText: initialSearchText))
    }

    var body: some View {
        #if os(tvOS)
            LogContentInnerView(dataModel: viewModel.dataModel, viewModel: viewModel)
        #else
            contentWithToolbar
                .onDisappear {
                    environments.logSearchText = viewModel.searchText
                }
                .alert($viewModel.alert)
                .background(
                    LogExportView(
                        dataModel: viewModel.dataModel,
                        alert: $viewModel.alert
                    )
                )
            #if os(iOS)
                .onAppear {
                    Task { await reloadRemoteServers() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .remoteServersUpdated)) { _ in
                    Task { await reloadRemoteServers() }
                }
            #endif
        #endif
    }

    #if !os(tvOS)
        private var searchableContent: some View {
            LogContentInnerView(dataModel: viewModel.dataModel, viewModel: viewModel)
                .applySearchable(text: $viewModel.searchText, isSearching: $viewModel.isSearching, shouldShow: viewModel.isSearching)
        }

        /// The iOS 15 fallback must be excluded from macOS builds entirely: with
        /// `if #available(iOS 16.0, *)` the else branch is compile-time dead on macOS,
        /// where the compiler permits unavailable declarations, so the Xcode 27 SDK
        /// resolved the HStack's ViewBuilder.buildBlock to the macOS 26-only
        /// `TupleContent` overload. That type still lands in this view's `Body`
        /// associated type witness, and demangling it aborts on macOS < 26
        /// (TestFlight crash in swift_getAssociatedTypeWitness).
        @ViewBuilder
        private var contentWithToolbar: some View {
            #if os(iOS)
                if #available(iOS 16.0, *) {
                    groupedToolbarContent
                } else {
                    // iOS 15 renders only one trailing toolbar entry; group all buttons into a single item
                    searchableContent.toolbar {
                        ToolbarItem {
                            HStack {
                                toolbarButtons
                                logMenu
                            }
                        }
                    }
                }
            #else
                groupedToolbarContent
            #endif
        }

        private var groupedToolbarContent: some View {
            searchableContent.toolbar {
                ToolbarItemGroup {
                    toolbarButtons
                    logMenu
                }
            }
        }

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
        }

        private var logMenu: AnyView {
            #if canImport(UIKit)
                if #available(iOS 16.0, *) {
                    return AnyView(LogMenuButton(
                        viewModel: viewModel,
                        remoteServers: remoteServers,
                        activeRemoteServerID: environments.remoteServer?.id,
                        onSelectLocalDevice: { environments.exitRemoteControl() },
                        onSelectRemoteServer: { server in
                            guard environments.remoteServer?.id != server.id else { return }
                            environments.enterRemoteControl(server)
                        }
                    ))
                } else {
                    // UIViewRepresentable views collapse to zero size in iOS 15 toolbars
                    return AnyView(LogMenuView(viewModel: viewModel, remoteServers: remoteServers))
                }
            #else
                return AnyView(LogMenuView(viewModel: viewModel))
            #endif
        }

        #if os(iOS)
            private func reloadRemoteServers() async {
                remoteServers = await (try? RemoteServerManager.list()) ?? []
            }
        #endif
    #endif
}

#if !os(tvOS)
    #if canImport(UIKit)
        private struct LogMenuButton: UIViewRepresentable {
            let viewModel: LogViewModel
            let remoteServers: [RemoteServer]
            let activeRemoteServerID: Int64?
            let onSelectLocalDevice: () -> Void
            let onSelectRemoteServer: (RemoteServer) -> Void
            @Environment(\.colorScheme) private var colorScheme

            func makeUIView(context _: Context) -> UIButton {
                let button = UIButton(type: .system)
                let config = UIImage.SymbolConfiguration(scale: .large)
                button.setImage(UIImage(systemName: "line.3.horizontal.circle", withConfiguration: config), for: .normal)
                if #available(iOS 26.0, *) {
                    button.tintColor = colorScheme == .dark ? .white : .black
                }
                button.showsMenuAsPrimaryAction = true
                button.menu = createMenu()
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                return button
            }

            func updateUIView(_ uiView: UIButton, context _: Context) {
                uiView.menu = createMenu()
                if #available(iOS 17.0, *) {
                    uiView.tintColor = colorScheme == .dark ? .white : .black
                }
            }

            private func createMenu() -> UIMenu {
                let logLevelActions = [
                    UIAction(
                        title: NSLocalizedString("Default", comment: "Log level filter default option"),
                        state: viewModel.selectedLogLevel == nil ? .on : .off
                    ) { _ in
                        viewModel.selectedLogLevel = nil
                    },
                ] + LogLevel.allCases.map { level in
                    UIAction(
                        title: level.name,
                        state: viewModel.selectedLogLevel == level.rawValue ? .on : .off
                    ) { _ in
                        viewModel.selectedLogLevel = level.rawValue
                    }
                }

                let logLevelMenu = UIMenu(
                    title: NSLocalizedString("Log Level", comment: ""),
                    image: UIImage(systemName: "slider.horizontal.3"),
                    children: logLevelActions
                )

                let saveActions = [
                    UIAction(
                        title: NSLocalizedString("To Clipboard", comment: ""),
                        image: UIImage(systemName: "doc.on.clipboard")
                    ) { _ in
                        viewModel.dataModel.copyToClipboard()
                    },
                    UIAction(
                        title: NSLocalizedString("To File", comment: ""),
                        image: UIImage(systemName: "arrow.down.doc")
                    ) { _ in
                        viewModel.dataModel.prepareLogFile()
                        viewModel.dataModel.showFileExporter = true
                    },
                    UIAction(
                        title: NSLocalizedString("Share", comment: ""),
                        image: UIImage(systemName: "square.and.arrow.up")
                    ) { _ in
                        viewModel.dataModel.prepareLogFile()
                    },
                ]

                let saveMenu = UIMenu(
                    title: NSLocalizedString("Save", comment: ""),
                    image: UIImage(systemName: "square.and.arrow.down"),
                    children: saveActions
                )

                let clearAction = UIAction(
                    title: NSLocalizedString("Clear Logs", comment: "Clear all logs"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    viewModel.dataModel.clearLogs()
                }

                var children: [UIMenuElement] = [logLevelMenu, saveMenu, clearAction]

                if !remoteServers.isEmpty {
                    let remoteControlActions = [
                        UIAction(
                            title: NSLocalizedString("Local Device", comment: ""),
                            state: activeRemoteServerID == nil ? .on : .off
                        ) { _ in
                            onSelectLocalDevice()
                        },
                    ] + remoteServers.map { server in
                        UIAction(
                            title: server.displayName,
                            state: server.id == activeRemoteServerID ? .on : .off
                        ) { _ in
                            onSelectRemoteServer(server)
                        }
                    }

                    children.append(UIMenu(
                        title: NSLocalizedString("Remote Control", comment: ""),
                        options: .displayInline,
                        children: remoteControlActions
                    ))
                }

                return UIMenu(children: children)
            }
        }
    #endif

    private struct LogMenuView: View {
        let viewModel: LogViewModel
        var remoteServers: [RemoteServer] = []

        var body: some View {
            Menu {
                if #unavailable(iOS 16.0) {
                    // iOS 15 renders a bare Picker inline; wrap it to match the iOS 16+ submenu
                    Menu {
                        logLevelPicker
                    } label: {
                        Label("Log Level", systemImage: "slider.horizontal.3")
                    }
                } else {
                    logLevelPicker
                }
                Menu {
                    Button {
                        viewModel.dataModel.copyToClipboard()
                    } label: {
                        Label("To Clipboard", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        viewModel.dataModel.prepareLogFile()
                        viewModel.dataModel.showFileExporter = true
                    } label: {
                        Label("To File", systemImage: "arrow.down.doc")
                    }
                    Button {
                        viewModel.dataModel.prepareLogFile()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    viewModel.dataModel.clearLogs()
                } label: {
                    Label(NSLocalizedString("Clear Logs", comment: "Clear all logs"), systemImage: "trash")
                }
                RemoteControlMenuItems(servers: remoteServers)
            } label: {
                Label("Others", systemImage: "line.3.horizontal.circle")
            }
        }

        private var logLevelPicker: some View {
            Picker(selection: Binding(
                get: { viewModel.selectedLogLevel },
                set: { viewModel.selectedLogLevel = $0 }
            )) {
                Text(NSLocalizedString("Default", comment: "Log level filter default option")).tag(Int?.none)
                ForEach(LogLevel.allCases) { level in
                    Text(level.name).tag(Int?.some(level.rawValue))
                }
            } label: {
                Label("Log Level", systemImage: "slider.horizontal.3")
            }
        }
    }
#endif

private struct LogContentInnerView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @ObservedObject var dataModel: LogDataModel
    @ObservedObject var viewModel: LogViewModel
    @Environment(\.colorScheme) private var colorScheme
    private let logFont = Font.system(.caption2, design: .monospaced)

    var body: some View {
        Group {
            if Variant.screenshotMode {
                previewContent
            } else if dataModel.isEmpty {
                emptyContent
            } else if dataModel.visibleLogs.isEmpty {
                emptyContent
            } else {
                logScrollView
            }
        }
    }

    private var previewContent: some View {
        let logList = [
            "(packet-tunnel) log server started",
            "INFO[0000] router: updated default interface en0, index 11",
            "inbound/tun[0]: started at utun3",
            "sing-box started (1.666s)",
        ]
        #if os(tvOS)
            return ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(logList.indices, id: \.self) { index in
                        Text(contrastAdjustedText(for: logList[index]))
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

    private var emptyContent: some View {
        Group {
            if dataModel.isConnected {
                if dataModel.initialLogsReceived {
                    Text("Empty logs")
                } else {
                    ProgressView()
                }
            } else if environments.remoteServer != nil {
                Text("Connecting...").onAppear {
                    environments.connect()
                }
            } else {
                Text("Service not started").onAppear {
                    environments.connect()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logScrollView: some View {
        #if os(tvOS)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(dataModel.visibleLogs) { logEntry in
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
                .onChangeCompat(of: dataModel.visibleLogs.count) { _ in
                    if !viewModel.isPaused {
                        scrollToLastEntry(reader)
                    }
                }
            }
        #else
            LogTextView(
                logs: dataModel.visibleLogs,
                font: logFont,
                shouldAutoScroll: !viewModel.isPaused,
                searchText: viewModel.searchText
            )
        #endif
    }

    #if os(tvOS)
        private func contrastAdjustedText(for message: String) -> AttributedString {
            var attributedString = ANSIColors.parseAnsiString(message)
            let backgroundColor: UIColor = colorScheme == .dark ? .black : .white

            for run in attributedString.runs {
                if let fgColor = run.foregroundColor {
                    let uiColor = UIColor(fgColor)
                    let adjusted = uiColor.adjustedForContrast(against: backgroundColor)
                    attributedString[run.range].foregroundColor = Color(adjusted)
                }
            }

            return attributedString
        }

        private func highlightedText(for message: String) -> AttributedString {
            var attributedString = contrastAdjustedText(for: message)

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
            guard let lastEntry = dataModel.visibleLogs.last else { return }
            withAnimation {
                reader.scrollTo(lastEntry.id, anchor: .bottom)
            }
        }
    #endif
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

    /// Observes the data model directly: presentation state (`showFileExporter`,
    /// `logFileURL`) lives on `LogDataModel`, which the surrounding view does not
    /// observe, so closure-based bindings would only pick up changes on the next
    /// unrelated re-render — leaving the exporter/share sheet stuck until then.
    private struct LogExportView: View {
        @ObservedObject var dataModel: LogDataModel
        @Binding var alert: AlertState?
        @State private var showShareSheet = false

        var body: some View {
            Color.clear
                .fileExporter(
                    isPresented: $dataModel.showFileExporter,
                    document: dataModel.logFileURL.map { LogTextDocument(url: $0) },
                    contentType: .plainText,
                    defaultFilename: "logs.txt"
                ) { result in
                    dataModel.cleanupLogFile()
                    dataModel.logFileURL = nil
                    if case let .failure(error) = result {
                        alert = AlertState(action: "export log file", error: error)
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    if let url = dataModel.logFileURL {
                        #if os(iOS)
                            ShareViewController(activityItems: [url])
                        #elseif os(macOS)
                            ShareView(items: [url], alert: $alert)
                        #endif
                    }
                }
                .onChange(of: dataModel.logFileURL) { newValue in
                    if newValue != nil, !dataModel.showFileExporter {
                        showShareSheet = true
                    }
                }
                .onChange(of: showShareSheet) { newValue in
                    if !newValue {
                        dataModel.cleanupLogFile()
                        dataModel.logFileURL = nil
                    }
                }
        }
    }

    private struct LogTextDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            [.plainText]
        }

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
            @Binding var alert: AlertState?

            func makeNSView(context _: Context) -> NSView {
                NSView()
            }

            func updateNSView(_ nsView: NSView, context: Context) {
                // updateNSView re-runs whenever the observed data model publishes;
                // the picker must only be presented once per sheet appearance.
                guard !context.coordinator.didShowPicker else { return }
                context.coordinator.didShowPicker = true
                let picker = NSSharingServicePicker(items: items)
                DispatchQueue.main.async {
                    picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                }
            }

            func makeCoordinator() -> Coordinator {
                Coordinator()
            }

            final class Coordinator {
                var didShowPicker = false
            }
        }
    #endif
#endif
