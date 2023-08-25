import Foundation
import Libbox

public class CommandClient: ObservableObject {
    public enum ConnectionType {
        case status
        case groups
        case log
        case clashMode
    }

    private let connectionType: ConnectionType
    private let logMaxLines: Int
    private var commandClient: LibboxCommandClient?
    private var connectTask: Task<Void, Error>?

    @Published public var isConnected: Bool
    @Published public var status: LibboxStatusMessage?
    @Published public var groups: [LibboxOutboundGroup]?
    @Published public var logList: [String]
    @Published public var clashModeList: [String]
    @Published public var clashMode: String

    public init(_ connectionType: ConnectionType, logMaxLines: Int = 300) {
        self.connectionType = connectionType
        self.logMaxLines = logMaxLines
        logList = []
        clashModeList = []
        clashMode = ""
        isConnected = false
    }

    public func connect() {
        if isConnected {
            return
        }
        if let connectTask {
            connectTask.cancel()
        }
        connectTask = Task.detached {
            await self.connect0()
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

    private func connect0() async {
        let clientOptions = LibboxCommandClientOptions()
        switch connectionType {
        case .status:
            clientOptions.command = LibboxCommandStatus
        case .groups:
            clientOptions.command = LibboxCommandGroup
        case .log:
            clientOptions.command = LibboxCommandLog
        case .clashMode:
            clientOptions.command = LibboxCommandClashMode
        }
        clientOptions.statusInterval = Int64(2 * NSEC_PER_SEC)
        let client = LibboxNewCommandClient(clientHandler(self), clientOptions)!
        do {
            for i in 0 ..< 10 {
                try await Task.sleep(nanoseconds: UInt64(Double(100 + (i * 50)) * Double(NSEC_PER_MSEC)))
                try Task.checkCancellation()
                do {
                    try client.connect()
                    commandClient = client
                    return
                } catch {
                }
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
            DispatchQueue.main.sync {
                self.commandClient.isConnected = true
            }
        }

        func disconnected(_: String?) {
            DispatchQueue.main.sync {
                self.commandClient.isConnected = false
            }
        }

        func writeLog(_ message: String?) {
            guard let message else {
                return
            }
            var logList = commandClient.logList
            if logList.count > commandClient.logMaxLines {
                logList.removeFirst()
            }
            logList.append(message)
            DispatchQueue.main.sync {
                self.commandClient.logList = logList
            }
        }

        func writeStatus(_ message: LibboxStatusMessage?) {
            DispatchQueue.main.sync {
                self.commandClient.status = message
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
            DispatchQueue.main.sync {
                self.commandClient.groups = newGroups
            }
        }

        func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {
            DispatchQueue.main.sync {
                self.commandClient.clashModeList = modeList!.toArray()
                self.commandClient.clashMode = currentMode!
            }
        }

        func updateClashMode(_ newMode: String?) {
            DispatchQueue.main.sync {
                self.commandClient.clashMode = newMode!
            }
        }
    }
}
