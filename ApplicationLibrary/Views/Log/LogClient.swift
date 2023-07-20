import Foundation
import Libbox
import Library
import SwiftUI

public class LogClient: ObservableObject {
    private var maxLines: Int
    @Published public var isConnected: Bool
    @Published public var logList: [String]

    private var commandClient: LibboxCommandClient!
    private var connectTask: Task<Void, Error>?

    public init(_ maxLines: Int) {
        self.maxLines = maxLines
        isConnected = false
        logList = []
    }

    deinit {
        if let connectTask {
            connectTask.cancel()
        }
        if let commandClient {
            try? commandClient.disconnect()
        }
    }

    public func reconnect() {
        if ApplicationLibrary.inPreview {
            logList = [
                "(packet-tunnel) log server started",
                "INFO[0000] router: loaded geoip database: 250 codes",
                "INFO[0000] router: loaded geosite database: 1400 codes",
                "INFO[0000] router: updated default interface en0, index 11",
                "inbound/tun[0]: started at utun3",
                "sing-box started (1.666s)",
            ]
            isConnected = true
        } else {
            if isConnected {
                return
            }
            if let connectTask {
                connectTask.cancel()
            }
            connectTask = Task.detached {
                await self.connect()
            }
        }
    }

    private func connect() async {
        let clientOptions = LibboxCommandClientOptions()
        clientOptions.command = LibboxCommandLog
        clientOptions.statusInterval = Int64(2 * NSEC_PER_SEC)
        let client = LibboxNewCommandClient(FilePath.sharedDirectory.relativePath, logHandler(self), clientOptions)!

        do {
            for i in 0 ..< 10 {
                try await Task.sleep(nanoseconds: UInt64(Double(100 + (i * 50)) * Double(NSEC_PER_MSEC)))
                try Task.checkCancellation()
                let isConnected: Bool
                do {
                    try client.connect()
                    isConnected = true
                } catch {
                    isConnected = false
                }
                try Task.checkCancellation()
                if isConnected {
                    commandClient = client
                    return
                }
            }
        } catch {
            try? client.disconnect()
        }
    }

    private class logHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private let logClient: LogClient

        init(_ logClient: LogClient) {
            self.logClient = logClient
        }

        @MainActor
        func connected() {
            logClient.logList.removeAll()
            logClient.isConnected = true
        }

        @MainActor
        func disconnected(_ message: String?) {
            if let message {
                logClient.logList.append("(log client closed) \(message)")
            } else {
                logClient.logList.append("(log client closed)")
            }
            try? logClient.commandClient?.disconnect()
            logClient.commandClient = nil
            logClient.isConnected = false
        }

        @MainActor
        func writeLog(_ message: String?) {
            guard let message else {
                return
            }
            if logClient.logList.count > logClient.maxLines {
                logClient.logList.removeFirst()
            }
            logClient.logList.append(message)
        }

        func writeStatus(_: LibboxStatusMessage?) {}
        func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
    }
}
