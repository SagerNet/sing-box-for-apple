import Library
import SwiftUI

@MainActor
public struct TailscaleSSHPromptView: View {
    private let peer: TailscalePeerData
    private let endpointTag: String
    @Binding private var presentedSession: TailscaleSSHPresentedSession?
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = "root"
    @State private var rememberedMap: [String: String] = [:]
    @State private var terminalType: String = defaultTerminalType
    @State private var rememberedTerminalTypes: [String: String] = [:]
    @State private var rememberSSHOptions = false

    private static let defaultTerminalType = "xterm-256color"

    public init(
        peer: TailscalePeerData,
        endpointTag: String,
        presentedSession: Binding<TailscaleSSHPresentedSession?>
    ) {
        self.peer = peer
        self.endpointTag = endpointTag
        _presentedSession = presentedSession
    }

    public var body: some View {
        FormView {
            Section {
                FormItem(String(localized: "Username")) {
                    TextField("Username", text: $username, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    #endif
                }
                FormItem(String(localized: "Terminal Type")) {
                    TextField("Terminal Type", text: $terminalType, prompt: Text(Self.defaultTerminalType))
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    #endif
                }
            } header: {
                Text("SSH Options")
            } footer: {
                Text("You can customize the terminal appearance by editing the Ghostty Configuration in App Settings.")
            }
            Section {
                Toggle("Remember SSH Options", isOn: $rememberSSHOptions)
                    .onChangeCompat(of: rememberSSHOptions) { newValue in
                        Task {
                            var qcPeers = await SharedPreferences.tailscaleSSHQuickConnectPeers.get()
                            if newValue {
                                qcPeers.insert(peer.stableID)
                            } else {
                                qcPeers.remove(peer.stableID)
                            }
                            await SharedPreferences.tailscaleSSHQuickConnectPeers.set(qcPeers)
                        }
                    }
            } header: {
                Text("Quick Connect")
            } footer: {
                Text("If enabled, you will need to long press the `Connect via SSH` button and select `Edit Connect Options` to change settings.\nTip: Long press on SSH-capable peers in the peer list to quickly connect via the context menu.")
            }
        }
        .navigationTitle(peer.hostName)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { connect() }
                        .disabled(trimmedUsername.isEmpty)
                }
            }
            .task {
                await loadRemembered()
            }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTerminalType: String {
        terminalType.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadRemembered() async {
        rememberedMap = await SharedPreferences.tailscaleSSHRememberedUsernames.get()
        if let saved = rememberedMap[peer.stableID], !saved.isEmpty {
            username = saved
        }
        rememberedTerminalTypes = await SharedPreferences.tailscaleSSHRememberedTerminalTypes.get()
        if let saved = rememberedTerminalTypes[peer.stableID], !saved.isEmpty {
            terminalType = saved
        }
        let quickPeers = await SharedPreferences.tailscaleSSHQuickConnectPeers.get()
        rememberSSHOptions = quickPeers.contains(peer.stableID)
    }

    private func connect() {
        let trimmed = trimmedUsername
        var map = rememberedMap
        if trimmed == "root" {
            map.removeValue(forKey: peer.stableID)
        } else {
            map[peer.stableID] = trimmed
        }

        let trimmedTerm = trimmedTerminalType
        let effectiveTerm = trimmedTerm.isEmpty ? Self.defaultTerminalType : trimmedTerm
        var termMap = rememberedTerminalTypes
        if effectiveTerm == Self.defaultTerminalType {
            termMap.removeValue(forKey: peer.stableID)
        } else {
            termMap[peer.stableID] = effectiveTerm
        }

        Task.detached {
            await SharedPreferences.tailscaleSSHRememberedUsernames.set(map)
            await SharedPreferences.tailscaleSSHRememberedTerminalTypes.set(termMap)
        }

        presentedSession = TailscaleSSHPresentedSession(
            endpointTag: endpointTag,
            peerHostName: peer.hostName,
            peerAddress: peer.tailscaleIPs.first!,
            username: trimmed,
            terminalType: effectiveTerm,
            hostKeys: peer.sshHostKeys
        )
        dismiss()
    }
}
