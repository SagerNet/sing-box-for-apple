#if os(tvOS)

    import DeviceDiscoveryUI
    import Libbox
    import Library
    import Network
    import SwiftUI

    @MainActor
    public final class ImportProfileViewModel: BaseViewModel {
        @Published public var selected = false
        @Published public var connection: NWConnection?
        @Published public var socket: NWSocket?
        @Published public var profiles: [LibboxProfilePreview]?
        @Published public var isImporting = false
        @Published public var importSucceeded = false

        public func reset() {
            if let connection {
                connection.stateUpdateHandler = nil
                connection.cancel()
                self.connection = nil
            }
            if let socket {
                socket.cancel()
                self.socket = nil
            }
            selected = false
            profiles = nil
        }

        public func handleEndpoint(_ endpoint: NWEndpoint, environments: ExtensionEnvironments) async {
            let connection = NWConnection(to: endpoint, using: NWParameters.applicationService)
            self.connection = connection
            socket = NWSocket(connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    DispatchQueue.main.async { [self] in
                        reset()
                        alert = AlertState(error: error)
                    }
                default: break
                }
            }
            connection.start(queue: .global())
            do {
                try await loopMessages(environments: environments)
            } catch {
                alert = AlertState(error: error)
                reset()
            }
        }

        private nonisolated func loopMessages(environments: ExtensionEnvironments) async throws {
            guard let socket = await socket else {
                return
            }
            var message: Data
            while true {
                do {
                    message = try socket.read()
                } catch {
                    throw NSError(domain: "read from connection: \(error.localizedDescription)", code: 0)
                }
                var error: NSError?
                switch Int64(message[0]) {
                case LibboxMessageTypeError:
                    let message = LibboxDecodeErrorMessage(message, &error)
                    if let error {
                        throw error
                    }
                    if let message {
                        throw NSError(domain: "remote error: \(message.message)", code: 0)
                    }
                case LibboxMessageTypeProfileList:
                    let decoder = LibboxProfileDecoder()
                    try decoder.decode(message)
                    let iterator = decoder.iterator()!
                    var profiles = [LibboxProfilePreview]()
                    while iterator.hasNext() {
                        let profile = iterator.next()!
                        if profile.type == LibboxProfileTypeiCloud {
                            continue
                        }
                        profiles.append(profile)
                    }
                    await MainActor.run { [self, profiles] in
                        self.profiles = profiles
                        isImporting = false
                    }
                case LibboxMessageTypeProfileContent:
                    let content = LibboxDecodeProfileContent(message, &error)
                    if let error {
                        throw error
                    }
                    try await importProfile(content!, environments: environments)
                    return
                default:
                    throw NSError(domain: "unknown message type \(message[0])", code: 0)
                }
            }
        }

        public func selectProfile(profileID: Int64) {
            guard let connection else {
                return
            }
            guard let socket else {
                return
            }
            connection.stateUpdateHandler = nil
            let request = LibboxProfileContentRequest()
            request.profileID = profileID
            do {
                try socket.write(request.encode())
                isImporting = true
            } catch {
                alert = AlertState(error: error)
                reset()
            }
        }

        private nonisolated func importProfile(_ content: LibboxProfileContent, environments: ExtensionEnvironments) async throws {
            var type: ProfileType = .local
            switch content.type {
            case LibboxProfileTypeLocal:
                type = .local
            case LibboxProfileTypeiCloud:
                type = .icloud
            case LibboxProfileTypeRemote:
                type = .remote
            default:
                break
            }
            let nextProfileID = try await ProfileManager.nextID()
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            try content.config.write(to: profileConfig, atomically: true, encoding: .utf8)
            var lastUpdated: Date?
            if content.lastUpdated > 0 {
                lastUpdated = Date(timeIntervalSince1970: Double(content.lastUpdated))
            }
            let uniqueProfileName = try await ProfileManager.uniqueName(content.name)
            try await ProfileManager.create(Profile(name: uniqueProfileName, type: type, path: profileConfig.relativePath, remoteURL: content.remotePath, autoUpdate: content.autoUpdate, lastUpdated: lastUpdated))
            await reset()
            await MainActor.run {
                environments.profileUpdate.send()
                importSucceeded = true
            }
        }
    }

#endif
