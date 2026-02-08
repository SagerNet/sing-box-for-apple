import Combine
import Foundation
import Libbox
import os

private let logger = Logger(category: "CommandClient")

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

public struct TrafficSnapshot {
    public var status: LibboxStatusMessage?
    public var uplinkHistory: [CGFloat]
    public var downlinkHistory: [CGFloat]

    public init(
        status: LibboxStatusMessage? = nil,
        uplinkHistory: [CGFloat] = Array(repeating: 0, count: 30),
        downlinkHistory: [CGFloat] = Array(repeating: 0, count: 30)
    ) {
        self.status = status
        self.uplinkHistory = uplinkHistory
        self.downlinkHistory = downlinkHistory
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
    private var connectTask: Task<Void, Never>?
    private var activeConnectionToken: UInt64 = 0
    private var isConnecting = false
    @Published public var isConnected: Bool
    // Coalesce traffic updates so SwiftUI re-renders once per status tick.
    @Published private var trafficSnapshot = TrafficSnapshot()
    public var status: LibboxStatusMessage? {
        trafficSnapshot.status
    }

    public var statusPublisher: AnyPublisher<LibboxStatusMessage?, Never> {
        $trafficSnapshot
            .map(\.status)
            .eraseToAnyPublisher()
    }

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
    private var connectionsStore: LibboxConnections?

    public var uplinkHistory: [CGFloat] {
        trafficSnapshot.uplinkHistory
    }

    public var downlinkHistory: [CGFloat] {
        trafficSnapshot.downlinkHistory
    }

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

    public func setupMockData() {
        isConnected = true
        clashModeList = ["rule", "global", "direct"]
        clashMode = "rule"
        trafficSnapshot = TrafficSnapshot(
            uplinkHistory: Array(repeating: CGFloat(1000), count: 30),
            downlinkHistory: Array(repeating: CGFloat(5000), count: 30)
        )
        hasAnyConnection = true
    }

    public func connect() {
        if isConnected || isConnecting {
            return
        }
        if let commandClient {
            try? commandClient.disconnect()
            self.commandClient = nil
        }
        isConnecting = true
        activeConnectionToken &+= 1
        let token = activeConnectionToken
        connectTask = Task { [weak self] in
            await self?.performConnection(token: token)
        }
    }

    public func disconnect() {
        if let connectTask {
            connectTask.cancel()
            self.connectTask = nil
        }
        isConnecting = false
        activeConnectionToken &+= 1
        if let commandClient {
            try? commandClient.disconnect()
            self.commandClient = nil
        }
        if isConnected {
            isConnected = false
        }
    }

    private func flushPendingLogs() {
        logBatchTimer = nil
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

    public func clearLogs() {
        logBatchTimer?.cancel()
        logBatchTimer = nil
        pendingLogs.removeAll()
        logList.removeAll()
    }

    public func filterConnectionsNow() {
        guard let store = connectionsStore else {
            return
        }
        let result = filterConnections(store)
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

    private nonisolated func performConnection(token: UInt64) async {
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
        let client = LibboxNewCommandClient(clientHandler(self, connectionToken: token), clientOptions)!
        do {
            try client.connect()
        } catch {
            await finishConnectionAttempt(token: token, client: nil)
            return
        }
        await finishConnectionAttempt(token: token, client: client)
    }

    private func finishConnectionAttempt(token: UInt64, client: LibboxCommandClient?) async {
        await MainActor.run { [self] in
            defer {
                isConnecting = false
                connectTask = nil
            }
            guard token == activeConnectionToken else {
                if let client {
                    try? client.disconnect()
                }
                return
            }
            if let client {
                commandClient = client
            }
        }
    }

    private class clientHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private let commandClient: CommandClient
        private let connectionToken: UInt64

        init(_ commandClient: CommandClient, connectionToken: UInt64) {
            self.commandClient = commandClient
            self.connectionToken = connectionToken
        }

        private func isActiveConnection() -> Bool {
            commandClient.activeConnectionToken == connectionToken
        }

        func connected() {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                if commandClient.connectionTypes.contains(.log) {
                    commandClient.logList = []
                }
                commandClient.isConnected = true
            }
        }

        func disconnected(_ message: String?) {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.isConnected = false
            }
            if let message {
                logger.debug("client disconnected: \(message)")
            }
        }

        func setDefaultLogLevel(_ level: Int32) {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.defaultLogLevel = Int(level)
            }
        }

        func clearLogs() {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.clearLogs()
            }
        }

        func writeLogs(_ messageList: (any LibboxLogIteratorProtocol)?) {
            guard let messageList else {
                return
            }
            guard isActiveConnection() else { return }

            // Collect new logs
            var newLogs: [LogEntry] = []
            while messageList.hasNext() {
                let logEntry = messageList.next()!
                newLogs.append(LogEntry(level: Int(logEntry.level), message: logEntry.message))
            }

            guard !newLogs.isEmpty else { return }

            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.pendingLogs.append(contentsOf: newLogs)
                if commandClient.logBatchTimer == nil {
                    let workItem = DispatchWorkItem { [weak commandClient] in
                        guard let commandClient else { return }
                        commandClient.flushPendingLogs()
                    }
                    commandClient.logBatchTimer = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + commandClient.logBatchInterval, execute: workItem)
                }
            }
        }

        func writeStatus(_ message: LibboxStatusMessage?) {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                var snapshot = commandClient.trafficSnapshot
                snapshot.status = message
                if let message, message.trafficAvailable {
                    snapshot.uplinkHistory.removeFirst()
                    snapshot.uplinkHistory.append(CGFloat(message.uplink))

                    snapshot.downlinkHistory.removeFirst()
                    snapshot.downlinkHistory.append(CGFloat(message.downlink))
                }
                commandClient.trafficSnapshot = snapshot
            }
        }

        func writeGroups(_ groups: LibboxOutboundGroupIteratorProtocol?) {
            guard let groups else {
                return
            }
            guard isActiveConnection() else { return }
            var newGroups: [LibboxOutboundGroup] = []
            while groups.hasNext() {
                newGroups.append(groups.next()!)
            }
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.groups = newGroups
            }
        }

        func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.clashModeList = modeList!.toArray()
                commandClient.clashMode = currentMode!
            }
        }

        func updateClashMode(_ newMode: String?) {
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                commandClient.clashMode = newMode!
            }
        }

        func write(_ events: LibboxConnectionEvents?) {
            guard let events else {
                return
            }
            DispatchQueue.main.async { [self] in
                guard isActiveConnection() else { return }
                if commandClient.connectionsStore == nil {
                    commandClient.connectionsStore = LibboxNewConnections()
                }
                commandClient.connectionsStore?.apply(events)
                let result = commandClient.filterConnections(commandClient.connectionsStore!)
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
