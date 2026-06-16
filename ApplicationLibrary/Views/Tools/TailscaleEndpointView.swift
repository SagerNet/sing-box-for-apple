import Library
import SwiftUI

@MainActor
public struct TailscaleEndpointView: View {
    @ObservedObject var viewModel: TailscaleStatusViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthURLQRCode = false
    #if !os(tvOS)
        @State private var sshPromptPeer: TailscalePeerData?
        @State private var sshPresentedSession: TailscaleSSHPresentedSession?
        @State private var pendingSSHSession: TailscaleSSHPresentedSession?
    #endif
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    let endpointTag: String

    public init(viewModel: TailscaleStatusViewModel, endpointTag: String) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
    }

    private var endpoint: TailscaleEndpointData? {
        viewModel.endpoint(tag: endpointTag)
    }

    private var navigationTitleKey: LocalizedStringKey {
        viewModel.endpoints.count > 1 ? "Tailscale: \(endpointTag)" : "Tailscale"
    }

    public var body: some View {
        FormView {
            if let endpoint {
                Section("Status") {
                    FormTextItem("State", "power") {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(stateColor(endpoint.backendState))
                            Text(endpoint.backendState)
                        }
                    }
                    if endpoint.backendState == "Running", let selfPeer = endpoint.selfPeer {
                        FormNavigationLink {
                            TailscalePeerView(peer: selfPeer, endpointTag: endpointTag, isSelf: true, networkName: endpoint.networkName, canLogout: !endpoint.keyAuth, onLogout: {
                                Task {
                                    await viewModel.logout(endpointTag: endpointTag)
                                }
                            })
                        } label: {
                            HStack {
                                Label("This Device", systemImage: "laptopcomputer")
                                Spacer()
                                Text(selfPeer.displayName)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if endpoint.backendState == "Running", endpoint.hasExitNodeCandidates {
                        FormNavigationLink {
                            TailscaleExitNodePickerView(viewModel: viewModel, endpointTag: endpointTag)
                        } label: {
                            HStack {
                                Label("Exit Node", systemImage: "arrow.triangle.turn.up.right.diamond")
                                Spacer()
                                Text(endpoint.exitNode?.displayName ?? String(localized: "Disabled"))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if !endpoint.authURL.isEmpty {
                        if let url = URL(string: endpoint.authURL) {
                            #if !os(tvOS)
                                Link(destination: url) {
                                    Label("Open Auth URL", systemImage: "arrow.up.forward.app")
                                }
                            #endif
                            Button {
                                showAuthURLQRCode = true
                            } label: {
                                Label("Open Auth URL as QR Code", systemImage: "qrcode")
                            }
                        }
                    }
                }

                ForEach(endpoint.userGroups) { group in
                    Section {
                        ForEach(group.peers) { peer in
                            peerLink(peer, isSelf: false)
                        }
                    } header: {
                        Text(group.displayName.isEmpty ? group.loginName : group.displayName)
                    }
                }
            }
        }
        .navigationTitle(navigationTitleKey)
        .sheet(isPresented: $showAuthURLQRCode) {
            if let endpoint {
                URLQRCodeSheet(url: endpoint.authURL, title: String(localized: "Auth URL"))
            }
        }
        .onChangeCompat(of: endpoint == nil) { isNil in
            if isNil {
                dismiss()
            }
        }
        #if !os(tvOS)
        .platformSheet(item: $sshPromptPeer, size: PlatformSheetSize(minWidth: 360, minHeight: 220), onDismiss: {
            if let session = pendingSSHSession {
                pendingSSHSession = nil
                sshPresentedSession = session
            }
        }) { peer in
            TailscaleSSHPromptView(peer: peer, endpointTag: endpointTag, onConnect: { session in pendingSSHSession = session })
        }
            #if os(iOS)
        .sheet(item: $sshPresentedSession) { presented in
            NavigationStackCompat {
                TerminalSessionContainerView(presented)
            }
        }
            #elseif os(macOS)
        .onChangeCompat(of: sshPresentedSession) { newValue in
            guard let newValue else { return }
            openWindow(value: newValue)
            sshPresentedSession = nil
        }
            #endif
        #endif
    }

    private func peerLink(_ peer: TailscalePeerData, isSelf: Bool) -> some View {
        FormNavigationLink {
            TailscalePeerView(peer: peer, endpointTag: endpointTag, isSelf: isSelf)
        } label: {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(peer.online ? .green : Color(.systemGray))
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName)
                    if let firstIP = peer.tailscaleIPs.first {
                        Text(firstIP)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let badges = peerBadges(peer)
                    if !badges.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(badges) { badge in
                                peerBadgeView(badge)
                            }
                        }
                    }
                }
            }
        }
        #if !os(tvOS)
        .contextMenu {
            if !peer.sshHostKeys.isEmpty, peer.online, !isSelf, !peer.tailscaleIPs.isEmpty {
                Button {
                    handleSSHFromPeerList(peer)
                } label: {
                    Label("Connect via SSH", systemImage: "terminal")
                }
            }
        }
        #endif
    }

    #if !os(tvOS)
        private func handleSSHFromPeerList(_ peer: TailscalePeerData) {
            Task {
                let quickPeers = await SharedPreferences.tailscaleSSHQuickConnectPeers.get()
                if quickPeers.contains(peer.stableID) {
                    let usernames = await SharedPreferences.tailscaleSSHRememberedUsernames.get()
                    let termTypes = await SharedPreferences.tailscaleSSHRememberedTerminalTypes.get()
                    #if os(macOS)
                        let forwardAgent = await SharedPreferences.tailscaleSSHForwardAgent.get()
                    #else
                        let forwardAgent = false
                    #endif
                    sshPresentedSession = TailscaleSSHPresentedSession(
                        endpointTag: endpointTag,
                        peerHostName: peer.hostName,
                        peerAddress: peer.tailscaleIPs.first!,
                        username: usernames[peer.stableID] ?? "root",
                        terminalType: termTypes[peer.stableID] ?? "xterm-256color",
                        hostKeys: peer.sshHostKeys,
                        forwardAgent: forwardAgent
                    )
                } else {
                    sshPromptPeer = peer
                }
            }
        }
    #endif

    private func peerBadges(_ peer: TailscalePeerData) -> [PeerBadge] {
        guard peer.online else { return [] }
        var badges: [PeerBadge] = []
        if peer.shareeNode {
            badges.append(PeerBadge(id: "sharee", text: "Shared in", color: .red))
        }
        if peer.exitNodeOption {
            badges.append(PeerBadge(id: "exit", text: "Exit Node", color: .blue))
        }
        if peer.expired {
            badges.append(PeerBadge(id: "expired", text: "Expired", color: .red))
        } else if peer.keyExpiry > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(peer.keyExpiry))
            let now = Date()
            let oneMonth: TimeInterval = 30 * 24 * 60 * 60
            if date.timeIntervalSince(now) <= oneMonth {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: date, relativeTo: now)
                badges.append(PeerBadge(id: "expires", text: "Expires \(relative)", color: .gray))
            }
        } else {
            badges.append(PeerBadge(id: "expiry-disabled", text: "Key expiry disabled", color: .gray))
        }
        if !peer.sshHostKeys.isEmpty {
            badges.append(PeerBadge(id: "ssh", text: "SSH", color: .green))
        }
        return badges
    }

    private func peerBadgeView(_ badge: PeerBadge) -> some View {
        Text(badge.text)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badge.color, in: Capsule())
    }

    private struct PeerBadge: Identifiable {
        let id: String
        let text: LocalizedStringKey
        let color: Color
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "Running": .green
        case "NeedsLogin", "NeedsMachineAuth": .orange
        case "Starting": .yellow
        default: Color(.systemGray)
        }
    }
}
