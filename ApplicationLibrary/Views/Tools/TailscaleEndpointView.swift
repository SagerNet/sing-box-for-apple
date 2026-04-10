import Library
import SwiftUI

@MainActor
public struct TailscaleEndpointView: View {
    @ObservedObject var viewModel: TailscaleStatusViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthURLQRCode = false
    let endpointTag: String

    public init(viewModel: TailscaleStatusViewModel, endpointTag: String) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
    }

    private var endpoint: TailscaleEndpointData? {
        viewModel.endpoint(tag: endpointTag)
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
                    if !endpoint.networkName.isEmpty {
                        FormTextItem("Network", "network") {
                            Text(endpoint.networkName)
                        }
                    }
                    if !endpoint.magicDNSSuffix.isEmpty {
                        FormTextItem("MagicDNS", "globe") {
                            Text(endpoint.magicDNSSuffix)
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

                if endpoint.backendState == "Running", let selfPeer = endpoint.selfPeer {
                    Section("This Device") {
                        peerLink(selfPeer, isSelf: true)
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
        .navigationTitle(endpointTag)
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
    }

    private func peerLink(_ peer: TailscalePeerData, isSelf: Bool) -> some View {
        FormNavigationLink {
            TailscalePeerView(peer: peer, endpointTag: endpointTag, isSelf: isSelf)
        } label: {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(peer.online ? .green : Color(.systemGray))
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.hostName)
                    if let firstIP = peer.tailscaleIPs.first {
                        Text(firstIP)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
