import Library
import NetworkExtension
import SwiftUI

@MainActor
public struct ToolsView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var peerStore: TailscaleSSHPeerStore
    @StateObject private var viewModel = SettingViewModel()
    @StateObject private var tailscaleViewModel = TailscaleStatusViewModel()
    @StateObject private var usbipViewModel = USBIPStatusViewModel()
    #if os(macOS)
        @StateObject private var usbipProviderViewModel = USBIPProviderViewModel()
    #endif
    #if os(iOS)
        @State private var showCrashReportList = false
        @State private var showOOMReportList = false
        @State private var remoteServers: [RemoteServer] = []
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
                                        Button(info.peer.hostName) {
                                            handleSSH(info)
                                        }
                                    }
                                }
                            }
                        }
                        #endif
                    }
                }
            }

            if !usbipViewModel.servers.isEmpty {
                Section("Services") {
                    ForEach(usbipViewModel.servers) { server in
                        FormNavigationLink {
                            #if os(macOS)
                                USBIPServerView(viewModel: usbipViewModel, serverTag: server.serverTag)
                                    .environmentObject(usbipProviderViewModel)
                            #else
                                USBIPServerView(viewModel: usbipViewModel, serverTag: server.serverTag)
                            #endif
                        } label: {
                            if usbipViewModel.servers.count == 1 {
                                Label("USB/IP", systemImage: "externaldrive.connected.to.line.below")
                            } else {
                                Label("USB/IP: \(server.serverTag)", systemImage: "externaldrive.connected.to.line.below")
                            }
                        }
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

            // Crash/OOM reports and device checks read the local device, which the
            // remote control API does not reach.
            if environments.remoteServer == nil {
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
        }
        .modifier(ConnectionLifecycleObserver(profile: environments.extensionProfile, remoteServerID: environments.remoteServer?.id, onActive: { tailscaleViewModel.subscribe() }, onInactive: { tailscaleViewModel.cancel() }))
        .modifier(ConnectionLifecycleObserver(profile: environments.extensionProfile, remoteServerID: environments.remoteServer?.id, onActive: { usbipViewModel.subscribe() }, onInactive: { usbipViewModel.cancel() }))
        #if os(macOS)
            .modifier(ConnectionLifecycleObserver(profile: environments.extensionProfile, remoteServerID: environments.remoteServer?.id, onActive: { usbipProviderViewModel.start() }, onInactive: { usbipProviderViewModel.cancel() }))
        #endif
            .alert($tailscaleViewModel.alert)
            .onAppear { tailscaleViewModel.peerStore = peerStore }
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !remoteServers.isEmpty {
                        othersMenu
                    }
                }
            }
            .onAppear {
                Task { await reloadRemoteServers() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .remoteServersUpdated)) { _ in
                Task { await reloadRemoteServers() }
            }
        #endif
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

    #if os(iOS)
        private var othersMenu: some View {
            Menu {
                RemoteControlMenuItems(servers: remoteServers)
            } label: {
                Label("Others", systemImage: "line.3.horizontal.circle")
            }
        }

        private func reloadRemoteServers() async {
            remoteServers = await (try? RemoteServerManager.list()) ?? []
        }
    #endif

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
                    #if os(macOS)
                        let forwardAgent = await SharedPreferences.tailscaleSSHForwardAgent.get()
                    #else
                        let forwardAgent = false
                    #endif
                    sshPresentedSession = TailscaleSSHPresentedSession(
                        endpointTag: info.endpointTag,
                        peerHostName: info.peer.hostName,
                        peerAddress: info.peer.tailscaleIPs.first!,
                        username: usernames[info.peer.stableID] ?? "root",
                        terminalType: termTypes[info.peer.stableID] ?? "xterm-256color",
                        hostKeys: info.peer.sshHostKeys,
                        forwardAgent: forwardAgent
                    )
                } else {
                    sshPromptEndpointTag = info.endpointTag
                    sshPromptPeer = info.peer
                }
            }
        }
    #endif
}

private struct ConnectionLifecycleObserver: ViewModifier {
    var profile: ExtensionProfile?
    var remoteServerID: Int64?
    var onActive: () -> Void
    var onInactive: () -> Void

    func body(content: Content) -> some View {
        content.background {
            if let profile {
                LocalServiceLifecycleTrigger(profile: profile, remoteServerID: remoteServerID, onActive: onActive, onInactive: onInactive)
            } else {
                RemoteServiceLifecycleTrigger(remoteServerID: remoteServerID, onActive: onActive, onInactive: onInactive)
            }
        }
    }
}

private struct LocalServiceLifecycleTrigger: View {
    @ObservedObject var profile: ExtensionProfile
    var remoteServerID: Int64?
    var onActive: () -> Void
    var onInactive: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                if remoteServerID != nil || profile.status.isConnectedStrict {
                    onActive()
                }
            }
            .onChangeCompat(of: remoteServerID) { newValue in
                onInactive()
                if newValue != nil || profile.status.isConnectedStrict {
                    onActive()
                }
            }
            .onChangeCompat(of: profile.status) { status in
                guard remoteServerID == nil else { return }
                if status.isConnectedStrict {
                    onActive()
                } else {
                    onInactive()
                }
            }
    }
}

private struct RemoteServiceLifecycleTrigger: View {
    var remoteServerID: Int64?
    var onActive: () -> Void
    var onInactive: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                if remoteServerID != nil {
                    onActive()
                }
            }
            .onChangeCompat(of: remoteServerID) { newValue in
                onInactive()
                if newValue != nil {
                    onActive()
                }
            }
    }
}
