import Library
import SwiftUI

@MainActor
public struct TailscaleSSHPromptView: View {
    private let peer: TailscalePeerData
    private let endpointTag: String
    private let onConnect: (TailscaleSSHPresentedSession) -> Void
    @EnvironmentObject private var peerStore: TailscaleSSHPeerStore
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = "root"
    @State private var rememberedMap: [String: String] = [:]
    @State private var terminalType: String = defaultTerminalType
    @State private var rememberedTerminalTypes: [String: String] = [:]
    @State private var rememberSSHOptions = false
    #if os(macOS)
        @State private var forwardAgent = false
    #endif

    private static let defaultTerminalType = "xterm-256color"

    public init(
        peer: TailscalePeerData,
        endpointTag: String,
        onConnect: @escaping (TailscaleSSHPresentedSession) -> Void
    ) {
        self.peer = peer
        self.endpointTag = endpointTag
        self.onConnect = onConnect
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
                #if os(macOS)
                    Toggle("Forward Agent", isOn: $forwardAgent)
                        .disabled(!Variant.useSystemExtension)
                    if !Variant.useSystemExtension {
                        Text("Only available in the macOS standalone version")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                #endif
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
                            peerStore.quickConnectPeerIDs = qcPeers
                        }
                    }
            } header: {
                Text("Quick Connect")
            } footer: {
                #if os(iOS)
                    Text("If enabled, you can quickly connect to this peer via the **context menu** (long press) on the Tailscale entry in Tools and on peer entries in the peer list.\n\nThis peer will also appear in the **New Session** menu when connected to other peers via SSH.")
                #else
                    Text("If enabled, you can quickly connect to this peer via the **context menu** (long press) on the Tailscale entry in Tools and on peer entries in the peer list.\n\nThis peer will also appear in the **New Window** menu when connected to other peers via SSH.")
                #endif
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
        #if os(macOS)
            forwardAgent = await SharedPreferences.tailscaleSSHForwardAgent.get()
        #endif
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

        #if os(macOS)
            let forwardAgentValue = forwardAgent
        #else
            let forwardAgentValue = false
        #endif

        Task.detached {
            await SharedPreferences.tailscaleSSHRememberedUsernames.set(map)
            await SharedPreferences.tailscaleSSHRememberedTerminalTypes.set(termMap)
            #if os(macOS)
                await SharedPreferences.tailscaleSSHForwardAgent.set(forwardAgentValue)
            #endif
        }

        onConnect(TailscaleSSHPresentedSession(
            endpointTag: endpointTag,
            peerHostName: peer.hostName,
            peerAddress: peer.tailscaleIPs.first!,
            username: trimmed,
            terminalType: effectiveTerm,
            hostKeys: peer.sshHostKeys,
            forwardAgent: forwardAgentValue
        ))
        dismiss()
    }
}
