import Combine
import Foundation
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
        .map { logList, defaultLogLevel, selectedLogLevel, searchText in
            let effectiveLevel = selectedLogLevel ?? defaultLogLevel
            return logList.filter { log in
                log.level <= effectiveLevel &&
                    (searchText.isEmpty || log.message.contains(searchText))
            }
        }
        .receive(on: DispatchQueue.main)
        .assign(to: &$filteredLogs)
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

    public func clearLogs() {
        commandClient.logList.removeAll()
        isPaused = false
    }

    #if !os(tvOS)
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

        public func prepareLogFile() {
            do {
                let text = getLogsText()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
                let dateString = dateFormatter.string(from: Date())
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
