import Foundation
import Libbox
import Network

public class ProfileServer {
    private var listener: NWListener

    @available(iOS 16.0, macOS 13.0, *)
    public init() throws {
        listener = try NWListener(using: .applicationService)
        listener.service = NWListener.Service(applicationService: "sing-box:profile")
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { state in
                if state == .ready {
                    Task.detached {
                        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 100)
                        await ProfileConnection(connection).process()
                    }
                }
            }
            connection.start(queue: .global())
        }
    }

    public func start() {
        listener.start(queue: .global())
    }

    public func cancel() {
        listener.cancel()
    }

    class ProfileConnection {
        private let connection: NWSocket

        init(_ connection: NWConnection) {
            self.connection = NWSocket(connection)
        }

        func process() async {
            do {
                try await writeProfilePreviewList()
            } catch {
                NSLog("profile server: write profile list: \(error.localizedDescription)")
                writeError(error.localizedDescription)
                return
            }
            do {
                while true {
                    let message = try connection.read()
                    try processMessage(message)
                }
            } catch {
                NSLog("profile server: process connection: \(error.localizedDescription)")
                writeError(error.localizedDescription)
            }
        }

        private func processMessage(_ data: Data) throws {
            if data.count == 0 {
                return
            }
            let messageType = Int64(data[0])
            switch messageType {
            case LibboxMessageTypeProfileContentRequest:
                Task {
                    try await processProfileContentRequest(data)
                }
            default:
                throw NSError(domain: "unexpected message type \(messageType)", code: 0)
            }
        }

        private func processProfileContentRequest(_ data: Data) async throws {
            var error: NSError?
            let request = LibboxDecodeProfileContentRequest(data, &error)
            if let error {
                throw error
            }

            let profile = try await ProfileManager.get(request!.profileID)
            guard let profile else {
                throw NSError(domain: "profile not found", code: 0)
            }
            let content = LibboxProfileContent()
            content.name = profile.name
            switch profile.type {
            case .local:
                content.type = LibboxProfileTypeLocal
            case .icloud:
                content.type = LibboxProfileTypeiCloud
            case .remote:
                content.type = LibboxProfileTypeRemote
            }
            content.config = try profile.read()
            if profile.type != .local {
                content.remotePath = profile.remoteURL!
            }
            if profile.type == .remote {
                content.autoUpdate = profile.autoUpdate
                content.autoUpdateInterval = profile.autoUpdateInterval
                if let lastUpdated = profile.lastUpdated {
                    content.lastUpdated = Int64(lastUpdated.timeIntervalSince1970)
                }
            }
            try connection.write(content.encode())
        }

        private func writeProfilePreviewList() async throws {
            let profiles = try await ProfileManager.list()
            let encoder = LibboxProfileEncoder()
            for profile in profiles {
                let preview = LibboxProfilePreview()
                preview.profileID = profile.mustID
                preview.name = profile.name
                switch profile.type {
                case .local:
                    preview.type = LibboxProfileTypeLocal
                case .icloud:
                    preview.type = LibboxProfileTypeiCloud
                case .remote:
                    preview.type = LibboxProfileTypeRemote
                }
                encoder.append(preview)
            }
            try connection.write(encoder.encode())
        }

        private func writeError(_ message: String) {
            let errorMessage = LibboxErrorMessage()
            errorMessage.message = message
            try? connection.write(errorMessage.encode())
        }
    }
}
