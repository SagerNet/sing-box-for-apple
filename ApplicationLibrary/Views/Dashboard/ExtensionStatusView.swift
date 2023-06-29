import Libbox
import Library
import SwiftUI

public struct ExtensionStatusView: View {
    @State private var commandClient: LibboxCommandClient?
    @State private var message: LibboxStatusMessage?
    @State private var connectTask: Task<Void, Error>?
    @State private var errorPresented = false
    @State private var errorMessage = ""

    private let infoFont = Font.system(.caption, design: .monospaced)

    public init() {}

    public var body: some View {
        viewBuilder {
            if let message {
                FormTextItem("Memory", LibboxFormatBytes(message.memory))
                FormTextItem("Goroutines", "\(message.goroutines)")
                FormTextItem("Connections", "\(message.connections)").contextMenu {
                    Button("Close", role: .destructive) {
                        Task.detached {
                            closeConnections()
                        }
                    }
                }
            } else {
                FormTextItem("Memory", "Loading...")
                FormTextItem("Goroutines", "Loading...")
                FormTextItem("Connections", "Loading...")
            }
        }

        .onAppear(perform: doReload)
        .onDisappear {
            connectTask?.cancel()
            if let commandClient {
                try? commandClient.disconnect()
            }
            commandClient = nil
        }
        .alert(isPresented: $errorPresented) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Ok"))
            )
        }
    }

    private func doReload() {
        connectTask?.cancel()
        connectTask = Task.detached {
            await connect()
        }
    }

    private func connect() async {
        let clientOptions = LibboxCommandClientOptions()
        clientOptions.command = LibboxCommandStatus
        clientOptions.statusInterval = Int64(2 * NSEC_PER_SEC)
        let client = LibboxNewCommandClient(FilePath.sharedDirectory.relativePath, statusHandler(self), clientOptions)!

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
            NSLog("failed to connect status: \(error.localizedDescription)")
            try? client.disconnect()
        }
    }

    private func closeConnections() {
        do {
            try LibboxNewStandaloneCommandClient(FilePath.sharedDirectory.relativePath)?.closeConnections()
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
        }
    }

    private class statusHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private let statusView: ExtensionStatusView

        init(_ statusView: ExtensionStatusView) {
            self.statusView = statusView
        }

        func connected() {}

        func disconnected(_: String?) {}

        func writeLog(_: String?) {}

        func writeStatus(_ message: LibboxStatusMessage?) {
            statusView.message = message
        }

        func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
    }
}
