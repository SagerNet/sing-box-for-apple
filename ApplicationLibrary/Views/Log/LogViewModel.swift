import Combine
import Foundation
import Library

@MainActor
public class LogViewModel: ObservableObject {
    @Published public var selectedLogLevel: Int?
    @Published public var isPaused = false
    @Published public var filteredLogs: [LogEntry] = []

    private let commandClient: CommandClient

    public var isEmpty: Bool { commandClient.logList.isEmpty }
    public var isConnected: Bool { commandClient.isConnected }

    public init(commandClient: CommandClient) {
        self.commandClient = commandClient

        Publishers.CombineLatest3(
            commandClient.$logList,
            commandClient.$defaultLogLevel,
            $selectedLogLevel
        )
        .map { logList, defaultLogLevel, selectedLogLevel in
            let effectiveLevel = selectedLogLevel ?? defaultLogLevel
            return logList.filter { $0.level <= effectiveLevel }
        }
        .receive(on: DispatchQueue.main)
        .assign(to: &$filteredLogs)
    }

    public func togglePause() {
        isPaused.toggle()
    }

    public func clearLogs() {
        commandClient.logList.removeAll()
        isPaused = false
    }
}
