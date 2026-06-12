#if os(iOS) || os(macOS)
    import Library
    import SwiftUI

    public struct RemoteControlMenuItems: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        private let servers: [RemoteServer]

        public init(servers: [RemoteServer]) {
            self.servers = servers
        }

        public var body: some View {
            if !servers.isEmpty {
                Section("Remote Control") {
                    // iOS 15 menus do not render section header text
                    if #unavailable(iOS 16.0) {
                        Text("Remote Control")
                    }
                    localDeviceButton
                    ForEach(servers) { server in
                        serverButton(server)
                    }
                    Button {
                        NotificationCenter.default.post(name: .navigateToSettingsPage, object: SettingsPage.remoteControl)
                    } label: {
                        Label("Manage Servers...", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }

        private var localDeviceButton: some View {
            Button {
                environments.exitRemoteControl()
            } label: {
                if environments.remoteServer == nil {
                    Label("Local Device", systemImage: "checkmark")
                } else {
                    Text("Local Device")
                }
            }
        }

        private func serverButton(_ server: RemoteServer) -> some View {
            let isActive = environments.remoteServer?.id == server.id
            return Button {
                guard !isActive else { return }
                environments.enterRemoteControl(server)
            } label: {
                if isActive {
                    Label(server.displayName, systemImage: "checkmark")
                } else {
                    Text(server.displayName)
                }
            }
        }
    }
#endif
