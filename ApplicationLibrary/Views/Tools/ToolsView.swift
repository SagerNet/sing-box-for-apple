import Library
import NetworkExtension
import SwiftUI

@MainActor
public struct ToolsView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = SettingViewModel()
    @StateObject private var tailscaleViewModel = TailscaleStatusViewModel()
    #if os(iOS)
        @State private var showCrashReportList = false
        @State private var showOOMReportList = false
    #endif
    #if !os(tvOS)
        @State private var sshPromptPeer: TailscalePeerData?
        @State private var sshPromptEndpointTag: String = ""
        @State private var sshPresentedSession: TailscaleSSHPresentedSession?
        @State private var pendingSSHSession: TailscaleSSHPresentedSession?
    #endif
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    public init() {}

    public var body: some View {
        FormView {
            if !tailscaleViewModel.endpoints.isEmpty {
                Section("Endpoints") {
                    ForEach(tailscaleViewModel.endpoints) { endpoint in
                        FormNavigationLink {
                            TailscaleEndpointView(viewModel: tailscaleViewModel, endpointTag: endpoint.endpointTag)
                        } label: {
                            if tailscaleViewModel.endpoints.count == 1 {
                                Label("Tailscale", systemImage: "point.3.filled.connected.trianglepath.dotted")
                            } else {
                                Label("Tailscale: \(endpoint.endpointTag)", systemImage: "point.3.filled.connected.trianglepath.dotted")
                            }
                        }
                        #if !os(tvOS)
                        .contextMenu {
                            if TailscaleSSHLaunchService.shared.terminalViewMaker != nil {
                                let sshPeers = sshAvailablePeers
                                if sshPeers.count == 1 {
                                    Button {
                                        handleSSH(sshPeers[0])
                                    } label: {
                                        Label("Connect via SSH", systemImage: "terminal")
                                    }
                                } else if sshPeers.count > 1 {
                                    Section("Connect via SSH") {
                                        ForEach(sshPeers) { info in
                                            Button {
                                                handleSSH(info)
                                            } label: {
                                                Label(info.peer.hostName, systemImage: "terminal")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        #endif
                    }
                }
            }

            Section("Network") {
                FormNavigationLink {
                    NetworkQualityView()
                } label: {
                    Label("Network Quality", systemImage: "network")
                }
                FormNavigationLink {
                    STUNTestView()
                } label: {
                    Label("STUN Test", systemImage: "arrow.triangle.swap")
                }
            }

            Section("Debug") {
                #if os(iOS)
                    NavigationLink(isActive: $showCrashReportList) {
                        CrashReportListView()
                    } label: {
                        Label("Crash Report", systemImage: "ladybug.fill")
                            .badge(environments.crashReportManager.unreadCount)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .reportReceived)) { notification in
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 300)
                            if let reportType = notification.object as? ReportType {
                                switch reportType {
                                case .crash:
                                    showCrashReportList = true
                                case .oom:
                                    showOOMReportList = true
                                }
                            }
                        }
                    }
                    NavigationLink(isActive: $showOOMReportList) {
                        OOMReportListView()
                    } label: {
                        Label("OOM Report", systemImage: "memorychip")
                            .badge(environments.oomReportManager.unreadCount)
                    }
                #else
                    FormNavigationLink {
                        CrashReportListView()
                    } label: {
                        #if os(tvOS)
                            HStack {
                                Label("Crash Report", systemImage: "ladybug.fill")
                                Spacer()
                                if environments.crashReportManager.unreadCount > 0 {
                                    Text(verbatim: "\(environments.crashReportManager.unreadCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        #else
                            Label("Crash Report", systemImage: "ladybug.fill")
                                .badge(environments.crashReportManager.unreadCount)
                        #endif
                    }
                #endif
                #if !os(iOS)
                    FormNavigationLink {
                        OOMReportListView()
                    } label: {
                        #if os(tvOS)
                            HStack {
                                Label("OOM Report", systemImage: "memorychip")
                                Spacer()
                                if environments.oomReportManager.unreadCount > 0 {
                                    Text(verbatim: "\(environments.oomReportManager.unreadCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        #else
                            Label("OOM Report", systemImage: "memorychip")
                                .badge(environments.oomReportManager.unreadCount)
                        #endif
                    }
                #endif
                FormTextItem("Taiwan Flag Available", "touchid") {
                    if viewModel.isLoading {
                        Text("Loading...")
                            .onAppear {
                                Task.detached {
                                    await viewModel.checkTaiwanFlagAvailability()
                                }
                            }
                    } else {
                        Text(viewModel.taiwanFlagAvailable.toString())
                    }
                }
            }
        }
        .modifier(TailscaleStatusObserver(profile: environments.extensionProfile, viewModel: tailscaleViewModel))
        .alert($tailscaleViewModel.alert)
        #if !os(tvOS)
            .platformSheet(item: $sshPromptPeer, size: PlatformSheetSize(minWidth: 360, minHeight: 220), onDismiss: {
                if let session = pendingSSHSession {
                    pendingSSHSession = nil
                    sshPresentedSession = session
                }
            }) { peer in
                TailscaleSSHPromptView(peer: peer, endpointTag: sshPromptEndpointTag, onConnect: { session in pendingSSHSession = session })
            }
            #if os(iOS)
            .sheet(item: $sshPresentedSession) { presented in
                NavigationStackCompat {
                    if let maker = TailscaleSSHLaunchService.shared.terminalViewMaker {
                        maker(presented)
                    }
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

    #if !os(tvOS)
        private struct SSHPeerInfo: Identifiable {
            var id: String {
                peer.stableID
            }

            let peer: TailscalePeerData
            let endpointTag: String
        }

        private var sshAvailablePeers: [SSHPeerInfo] {
            tailscaleViewModel.endpoints.flatMap { endpoint in
                endpoint.userGroups.flatMap { group in
                    group.peers.compactMap { peer in
                        guard peer.online, !peer.sshHostKeys.isEmpty, !peer.tailscaleIPs.isEmpty else { return nil }
                        return SSHPeerInfo(peer: peer, endpointTag: endpoint.endpointTag)
                    }
                }
            }
        }

        private func handleSSH(_ info: SSHPeerInfo) {
            Task {
                let quickPeers = await SharedPreferences.tailscaleSSHQuickConnectPeers.get()
                if quickPeers.contains(info.peer.stableID) {
                    let usernames = await SharedPreferences.tailscaleSSHRememberedUsernames.get()
                    let termTypes = await SharedPreferences.tailscaleSSHRememberedTerminalTypes.get()
                    sshPresentedSession = TailscaleSSHPresentedSession(
                        endpointTag: info.endpointTag,
                        peerHostName: info.peer.hostName,
                        peerAddress: info.peer.tailscaleIPs.first!,
                        username: usernames[info.peer.stableID] ?? "root",
                        terminalType: termTypes[info.peer.stableID] ?? "xterm-256color",
                        hostKeys: info.peer.sshHostKeys
                    )
                } else {
                    sshPromptEndpointTag = info.endpointTag
                    sshPromptPeer = info.peer
                }
            }
        }
    #endif
}

private struct TailscaleStatusObserver: ViewModifier {
    var profile: ExtensionProfile?
    var viewModel: TailscaleStatusViewModel

    func body(content: Content) -> some View {
        if let profile {
            content
                .modifier(ActiveObserver(profile: profile, viewModel: viewModel))
        } else {
            content
        }
    }

    private struct ActiveObserver: ViewModifier {
        @ObservedObject var profile: ExtensionProfile
        var viewModel: TailscaleStatusViewModel

        func body(content: Content) -> some View {
            content
                .onChangeCompat(of: profile.status) { status in
                    if status.isConnectedStrict {
                        viewModel.subscribe()
                    } else {
                        viewModel.cancel()
                    }
                }
                .onAppear {
                    if profile.status.isConnectedStrict {
                        viewModel.subscribe()
                    }
                }
        }
    }
}
