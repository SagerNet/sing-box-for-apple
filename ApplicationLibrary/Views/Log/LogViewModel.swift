import Combine
import Foundation
import Libbox
import Library
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
public class LogDataModel: ObservableObject {
    @Published public var filteredLogs: [LogEntry] = []
    @Published public private(set) var visibleLogs: [LogEntry] = []
    @Published public var showFileExporter = false
    @Published public var logFileURL: URL?

    private let commandClient: CommandClient
    private weak var viewModel: LogViewModel?
    private var lastProcessedLogCount = 0
    private var lastEffectiveLevel: Int?
    private var lastSearchText = ""
    private var cancellables = Set<AnyCancellable>()

    private static let maxVisibleLogs = 1000

    public var isEmpty: Bool {
        commandClient.logList.isEmpty
    }

    public var isConnected: Bool {
        commandClient.isConnected
    }

    private func updateVisibleLogs() {
        if filteredLogs.count <= Self.maxVisibleLogs {
            visibleLogs = filteredLogs
        } else {
            visibleLogs = Array(filteredLogs.suffix(Self.maxVisibleLogs))
        }
    }

    public init(commandClient: CommandClient, viewModel: LogViewModel) {
        self.commandClient = commandClient
        self.viewModel = viewModel

        let debouncedSearchText = viewModel.$searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)

        Publishers.CombineLatest4(
            commandClient.$logList,
            commandClient.$defaultLogLevel,
            viewModel.$selectedLogLevel,
            debouncedSearchText
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] logList, defaultLogLevel, selectedLogLevel, searchText in
            guard let self else { return }
            let effectiveLevel = selectedLogLevel ?? defaultLogLevel

            let canIncrement = self.lastProcessedLogCount > 0 &&
                logList.count > self.lastProcessedLogCount &&
                effectiveLevel == self.lastEffectiveLevel &&
                searchText == self.lastSearchText

            if canIncrement {
                let newLogs = logList[self.lastProcessedLogCount...]
                let newFilteredLogs = newLogs.filter { log in
                    log.level <= effectiveLevel &&
                        (searchText.isEmpty || log.message.contains(searchText))
                }
                self.filteredLogs.append(contentsOf: newFilteredLogs)
            } else {
                self.filteredLogs = logList.filter { log in
                    log.level <= effectiveLevel &&
                        (searchText.isEmpty || log.message.contains(searchText))
                }
            }

            self.updateVisibleLogs()
            self.lastProcessedLogCount = logList.count
            self.lastEffectiveLevel = effectiveLevel
            self.lastSearchText = searchText
        }
        .store(in: &cancellables)
    }

    public func clearLogs() {
        viewModel?.isPaused = false
        lastProcessedLogCount = 0
        lastEffectiveLevel = nil
        lastSearchText = ""
        filteredLogs = []
        visibleLogs = []
        commandClient.clearLogs()
        Task.detached {
            try? LibboxNewStandaloneCommandClient()!.clearLogs()
        }
    }

    public func getLogsText() -> String {
        filteredLogs.map(\.message).joined(separator: "\n")
    }

    #if !os(tvOS)
        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
            return formatter
        }()

        public func copyToClipboard() {
            let text = getLogsText()
            #if os(iOS)
                UIPasteboard.general.string = text
            #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #endif
        }

        public func cleanupLogFile() {
            guard let url = logFileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }

        public func prepareLogFile() {
            cleanupLogFile()
            do {
                let text = getLogsText()
                let dateString = Self.dateFormatter.string(from: Date())
                let tempDirectory = FileManager.default.temporaryDirectory
                let fileURL = tempDirectory.appendingPathComponent("logs-\(dateString).txt")
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
                logFileURL = fileURL
            } catch {
                viewModel?.alert = AlertState(action: "prepare log file", error: error)
            }
        }
    #endif
}

@MainActor
public class LogViewModel: BaseViewModel {
    @Published public var selectedLogLevel: Int?
    @Published public var isPaused = false
    @Published public var searchText = ""
    @Published public var isSearching = false

    public let commandClient: CommandClient
    public private(set) var dataModel: LogDataModel!

    public init(commandClient: CommandClient) {
        self.commandClient = commandClient
        super.init()
        dataModel = LogDataModel(commandClient: commandClient, viewModel: self)
    }

    public func togglePause() {
        isPaused.toggle()
    }

    public func toggleSearch() {
        isSearching.toggle()
        if !isSearching {
            searchText = ""
        }
    }
}
