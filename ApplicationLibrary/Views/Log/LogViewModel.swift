import Combine
import Foundation
import Library

@MainActor
public class LogViewModel: ObservableObject {
    @Published public var selectedLogLevel: Int?
    @Published public var isPaused = false
    @Published public var searchText = ""
    @Published public var isSearching = false
    @Published public var filteredLogs: [LogEntry] = []

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
}
