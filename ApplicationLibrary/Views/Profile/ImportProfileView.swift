#if os(tvOS)

    import DeviceDiscoveryUI
    import Libbox
    import Library
    import SwiftUI

    public struct ImportProfileView: View {
        @Environment(\.dismiss) private var dismiss

        @State private var isLoading = false
        @State private var selected = false
        @State private var alert: Alert?
        @State private var connection: NWSocket?
        @State private var profiles: [LibboxProfilePreview]?
        private let callback: () -> Void

        public init(callback: @escaping () -> Void) {
            self.callback = callback
        }

        public var body: some View {
            VStack {
                if !selected {
                    DevicePicker(
                        .applicationService(name: "sing-box:profile"))
                    { endpoint in
                        selected = true
                        Task.detached {
                            await handleEndpoint(endpoint)
                        }
                    } label: {
                        Text("Select Device")
                    } fallback: {
                        EmptyView()
                    } parameters: {
                        .applicationService
                    }
                } else if let profiles {
                    Form {
                        Text("\(profiles.count) Profiles")
                        ForEach(profiles, id: \.profileID) { profile in
                            Button(profile.name) {
                                isLoading = true
                                Task.detached {
                                    selectProfile(profileID: profile.profileID)
                                    isLoading = false
                                }
                            }.disabled(isLoading)
                        }
                    }
                } else {
                    Text("Connecting...")
                }
            }
            .focusSection()
            .alertBinding($alert)
            .navigationTitle("Import Profile")
        }

        private func reset() {
            selected = false
            profiles = nil
        }

        private func handleEndpoint(_ endpoint: NWEndpoint) async {
            let connection = NWConnection(to: endpoint, using: NWParameters.applicationService)
            self.connection = NWSocket(connection)
            connection.start(queue: .global())
            do {
                try loopMessages()
            } catch {
                alert = Alert(error)
                reset()
            }
        }

        private func loopMessages() throws {
            guard let connection else {
                return
            }
            while true {
                let message = try connection.read()
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
                            // not supported on tvOS
                            continue
                        }
                        profiles.append(profile)
                    }
                    self.profiles = profiles
                case LibboxMessageTypeProfileContent:
                    let content = LibboxDecodeProfileContent(message, &error)
                    if let error {
                        throw error
                    }
                    try importProfile(content!)
                default:
                    throw NSError(domain: "unknown message type \(message[0])", code: 0)
                }
            }
        }

        private func selectProfile(profileID: Int64) {
            guard let connection else {
                return
            }
            let request = LibboxProfileContentRequest()
            request.profileID = profileID
            do {
                try connection.write(request.encode())
            } catch {
                alert = Alert(error)
                reset()
            }
        }

        private func importProfile(_ content: LibboxProfileContent) throws {
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

            let nextProfileID = try ProfileManager.nextID()
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            try content.config.write(to: profileConfig, atomically: true, encoding: .utf8)
            var lastUpdated: Date?
            if content.lastUpdated > 0 {
                lastUpdated = Date(timeIntervalSince1970: Double(content.lastUpdated))
            }
            try ProfileManager.create(Profile(name: content.name, type: type, path: profileConfig.relativePath, remoteURL: content.remotePath, autoUpdate: content.autoUpdate, lastUpdated: lastUpdated))
            DispatchQueue.main.async {
                dismiss()
                callback()
            }
        }
    }

#endif
