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
public class LogViewModel: ObservableObject {
    @Published public var selectedLogLevel: Int?
    @Published public var isPaused = false
    @Published public var searchText = ""
    @Published public var isSearching = false
    @Published public var filteredLogs: [LogEntry] = []
    @Published public var alert: Alert?
    @Published public var showFileExporter = false
    @Published public var logFileURL: URL?

    private let commandClient: CommandClient
    private var lastProcessedLogCount = 0
    private var lastEffectiveLevel: Int?
    private var lastSearchText = ""

    public var isEmpty: Bool { commandClient.logList.isEmpty }
    public var isConnected: Bool { commandClient.isConnected }

    public init(commandClient: CommandClient) {
        self.commandClient = commandClient

        let debouncedSearchText = $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)

        Publishers.CombineLatest4(
            commandClient.$logList,
            commandClient.$defaultLogLevel,
            $selectedLogLevel,
            debouncedSearchText
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] logList, defaultLogLevel, selectedLogLevel, searchText in
            guard let self else { return }
            let effectiveLevel = selectedLogLevel ?? defaultLogLevel

            // Check if we can do incremental filtering
            let canIncrement = self.lastProcessedLogCount > 0 &&
                logList.count > self.lastProcessedLogCount &&
                effectiveLevel == self.lastEffectiveLevel &&
                searchText == self.lastSearchText

            if canIncrement {
                // Incremental filtering: only filter new logs
                let newLogs = logList[self.lastProcessedLogCount...]
                let newFilteredLogs = newLogs.filter { log in
                    log.level <= effectiveLevel &&
                        (searchText.isEmpty || log.message.contains(searchText))
                }
                self.filteredLogs.append(contentsOf: newFilteredLogs)
            } else {
                // Full refiltering needed
                self.filteredLogs = logList.filter { log in
                    log.level <= effectiveLevel &&
                        (searchText.isEmpty || log.message.contains(searchText))
                }
            }

            self.lastProcessedLogCount = logList.count
            self.lastEffectiveLevel = effectiveLevel
            self.lastSearchText = searchText
        }
        .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    public func togglePause() {
        isPaused.toggle()
    }

    public func toggleSearch() {
        isSearching.toggle()
        if !isSearching {
            searchText = ""
        }
    }

    public func clearLogs() {
        isPaused = false
        lastProcessedLogCount = 0
        lastEffectiveLevel = nil
        lastSearchText = ""
        Task.detached {
            let client = LibboxNewStandaloneCommandClient()
            try? client?.clearLogs()
        }
    }

    #if !os(tvOS)
        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
            return formatter
        }()

        public func getLogsText() -> String {
            filteredLogs.map(\.message).joined(separator: "\n")
        }

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
                alert = Alert(error)
            }
        }
    #endif
}
