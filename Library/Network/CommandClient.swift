import Foundation
import Libbox

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let level: Int
    public let message: String

    public init(level: Int, message: String) {
        self.level = level
        self.message = message
    }
}

public enum LogLevel: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case error = 2
    case warn = 3
    case info = 4
    case debug = 5
    case trace = 6

    public var name: String {
        switch self {
        case .error:
            return "Error"
        case .warn:
            return "Warn"
        case .info:
            return "Info"
        case .debug:
            return "Debug"
        case .trace:
            return "Trace"
        }
    }
}

public class CommandClient: ObservableObject {
    public enum ConnectionType {
        case status
        case groups
        case log
        case clashMode
        case connections
    }

    private let connectionTypes: [ConnectionType]
    private let logMaxLines: Int
    private var commandClient: LibboxCommandClient?
    private var connectTask: Task<Void, Error>?
    @Published public var isConnected: Bool
    @Published public var status: LibboxStatusMessage?
    @Published public var groups: [LibboxOutboundGroup]?
    @Published public var logList: [LogEntry]
    @Published public var defaultLogLevel = 0
    @Published public var selectedLogLevel: Int?
    @Published public var clashModeList: [String]
    @Published public var clashMode: String

    @Published public var connectionStateFilter = ConnectionStateFilter.active
    @Published public var connectionSort = ConnectionSort.byDate
    @Published public var connections: [LibboxConnection]?
    @Published public var hasAnyConnection: Bool = false
    public var rawConnections: LibboxConnections?

    @Published public var uplinkHistory: [CGFloat] = Array(repeating: 0, count: 30)
    @Published public var downlinkHistory: [CGFloat] = Array(repeating: 0, count: 30)

    // Batch processing for logs
    private var pendingLogs: [LogEntry] = []
    private var logBatchTimer: DispatchWorkItem?
    private let logBatchInterval: TimeInterval = 0.1 // 100ms batch window

    public init(_ connectionTypes: [ConnectionType], logMaxLines: Int = 3000) {
        self.connectionTypes = connectionTypes
        self.logMaxLines = logMaxLines
        logList = []
        clashModeList = []
        clashMode = ""
        isConnected = false
    }

    public convenience init(_ connectionType: ConnectionType, logMaxLines: Int = 300) {
        self.init([connectionType], logMaxLines: logMaxLines)
    }

    public func connect() {
        if isConnected {
            return
        }
        if let connectTask {
            connectTask.cancel()
        }
        connectTask = Task {
            await performConnection()
        }
    }

    public func disconnect() {
        if let connectTask {
            connectTask.cancel()
            self.connectTask = nil
        }
        if let commandClient {
            try? commandClient.disconnect()
            self.commandClient = nil
        }
    }

    private func flushPendingLogs() {
        guard !pendingLogs.isEmpty else { return }

        // Batch append all pending logs
        logList.append(contentsOf: pendingLogs)
        pendingLogs.removeAll()

        // Trim to max lines if needed
        if logList.count > logMaxLines {
            let removeCount = logList.count - logMaxLines
            logList.removeFirst(removeCount)
        }
    }

    public func filterConnectionsNow() {
        guard let message = rawConnections else {
            return
        }
        let result = filterConnections(message)
        connections = result.connections
        hasAnyConnection = result.hasAny
    }

    private func filterConnections(_ message: LibboxConnections) -> (connections: [LibboxConnection], hasAny: Bool) {
        let hasAny = message.iterator()?.hasNext() ?? false
        message.filterState(Int32(connectionStateFilter.rawValue))
        switch connectionSort {
        case .byDate:
            message.sortByDate()
        case .byTraffic:
            message.sortByTraffic()
        case .byTrafficTotal:
            message.sortByTrafficTotal()
        }
        let connectionIterator = message.iterator()!
        var connections: [LibboxConnection] = []
        while connectionIterator.hasNext() {
            connections.append(connectionIterator.next()!)
        }
        return (connections: connections, hasAny: hasAny)
    }

    private func initializeConnectionFilterState() async {
        let newFilter: ConnectionStateFilter = await .init(rawValue: SharedPreferences.connectionStateFilter.get()) ?? .active
        let newSort: ConnectionSort = await .init(rawValue: SharedPreferences.connectionSort.get()) ?? .byDate
        await MainActor.run {
            connectionStateFilter = newFilter
            connectionSort = newSort
        }
    }

    private nonisolated func performConnection() async {
        if connectionTypes.contains(.connections) {
            await initializeConnectionFilterState()
        }

        let clientOptions = LibboxCommandClientOptions()
        for connectionType in connectionTypes {
            switch connectionType {
            case .status:
                clientOptions.addCommand(LibboxCommandStatus)
            case .groups:
                clientOptions.addCommand(LibboxCommandGroup)
            case .log:
                clientOptions.addCommand(LibboxCommandLog)
            case .clashMode:
                clientOptions.addCommand(LibboxCommandClashMode)
            case .connections:
                clientOptions.addCommand(LibboxCommandConnections)
            }
        }
        clientOptions.statusInterval = Int64(NSEC_PER_SEC)
        let client = LibboxNewCommandClient(clientHandler(self), clientOptions)!
        do {
            for i in 0 ..< 10 {
                try await Task.sleep(nanoseconds: UInt64(Double(100 + (i * 50)) * Double(NSEC_PER_MSEC)))
                try Task.checkCancellation()
                do {
                    try client.connect()
                    await MainActor.run {
                        commandClient = client
                    }
                    return
                } catch {}
                try Task.checkCancellation()
            }
        } catch {
            try? client.disconnect()
        }
    }

    private class clientHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private let commandClient: CommandClient

        init(_ commandClient: CommandClient) {
            self.commandClient = commandClient
        }

        func connected() {
            DispatchQueue.main.async { [self] in
                if commandClient.connectionTypes.contains(.log) {
                    commandClient.logList = []
                }
                commandClient.isConnected = true
            }
        }

        func disconnected(_ message: String?) {
            DispatchQueue.main.async { [self] in
                commandClient.isConnected = false
            }
            if let message {
                NSLog("client disconnected: \(message)")
            }
        }

        func setDefaultLogLevel(_ level: Int32) {
            DispatchQueue.main.async { [self] in
                commandClient.defaultLogLevel = Int(level)
            }
        }

        func clearLogs() {
            DispatchQueue.main.async { [self] in
                commandClient.logList.removeAll()
            }
        }

        func writeLogs(_ messageList: (any LibboxLogIteratorProtocol)?) {
            guard let messageList else {
                return
            }

            // Collect new logs
            var newLogs: [LogEntry] = []
            while messageList.hasNext() {
                let logEntry = messageList.next()!
                newLogs.append(LogEntry(level: Int(logEntry.level), message: logEntry.message))
            }

            guard !newLogs.isEmpty else { return }

            DispatchQueue.main.async { [self] in
                // Add to pending batch
                commandClient.pendingLogs.append(contentsOf: newLogs)

                // Cancel existing timer
                commandClient.logBatchTimer?.cancel()

                // Schedule batch flush
                let workItem = DispatchWorkItem { [weak commandClient] in
                    guard let commandClient else { return }
                    commandClient.flushPendingLogs()
                }
                commandClient.logBatchTimer = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + commandClient.logBatchInterval, execute: workItem)
            }
        }

        func writeStatus(_ message: LibboxStatusMessage?) {
            DispatchQueue.main.async { [self] in
                commandClient.status = message
                if let message = message, message.trafficAvailable {
                    commandClient.uplinkHistory.removeFirst()
                    commandClient.uplinkHistory.append(CGFloat(message.uplink))
                    commandClient.downlinkHistory.removeFirst()
                    commandClient.downlinkHistory.append(CGFloat(message.downlink))
                }
            }
        }

        func writeGroups(_ groups: LibboxOutboundGroupIteratorProtocol?) {
            guard let groups else {
                return
            }
            var newGroups: [LibboxOutboundGroup] = []
            while groups.hasNext() {
                newGroups.append(groups.next()!)
            }
            DispatchQueue.main.async { [self] in
                commandClient.groups = newGroups
            }
        }

        func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {
            DispatchQueue.main.async { [self] in
                commandClient.clashModeList = modeList!.toArray()
                commandClient.clashMode = currentMode!
            }
        }

        func updateClashMode(_ newMode: String?) {
            DispatchQueue.main.async { [self] in
                commandClient.clashMode = newMode!
            }
        }

        func write(_ message: LibboxConnections?) {
            guard let message else {
                return
            }
            let result = commandClient.filterConnections(message)
            DispatchQueue.main.async { [self] in
                commandClient.rawConnections = message
                commandClient.connections = result.connections
                commandClient.hasAnyConnection = result.hasAny
            }
        }
    }
}

public enum ConnectionStateFilter: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case all
    case active
    case closed
}

public extension ConnectionStateFilter {
    var name: String {
        switch self {
        case .all:
            return NSLocalizedString("All", comment: "")
        case .active:
            return NSLocalizedString("Active", comment: "")
        case .closed:
            return NSLocalizedString("Closed", comment: "")
        }
    }
}

public enum ConnectionSort: Int, CaseIterable, Identifiable {
    public var id: Self {
        self
    }

    case byDate
    case byTraffic
    case byTrafficTotal
}

public extension ConnectionSort {
    var name: String {
        switch self {
        case .byDate:
            return NSLocalizedString("Date", comment: "")
        case .byTraffic:
            return NSLocalizedString("Traffic", comment: "")
        case .byTrafficTotal:
            return NSLocalizedString("Traffic Total", comment: "")
        }
    }
}
