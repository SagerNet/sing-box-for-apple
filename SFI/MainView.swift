import ApplicationLibrary
import Libbox
import Library
import NetworkExtension
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var selection = NavigationPage.dashboard
    @State private var importProfile: LibboxProfileContent?
    @State private var importRemoteProfile: LibboxImportRemoteProfile?
    @State private var alert: AlertState?
    @State private var showGroups = false
    @State private var showConnections = false
    @State private var buttonState = ButtonVisibilityState()

    private let profileEditor: (Binding<String>, Bool) -> AnyView = { text, isEditable in
        AnyView(RunestoneTextView(text: text, isEditable: isEditable))
    }

    private var shouldShowBottomAccessory: Bool {
        guard !environments.extensionProfileLoading else {
            return false
        }
        guard !environments.emptyProfiles else {
            return false
        }
        guard environments.extensionProfile != nil else {
            return false
        }
        return true
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var tabViewContent: some View {
        if shouldShowBottomAccessory {
            baseTabView
                .tabViewBottomAccessory {
                    HStack(spacing: 12) {
                        if let profile = environments.extensionProfile {
                            StatusText(profile: profile)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        NavigationButtonsView(
                            showGroupsButton: buttonState.showGroupsButton,
                            showConnectionsButton: buttonState.showConnectionsButton,
                            groupsCount: buttonState.groupsCount,
                            connectionsCount: buttonState.connectionsCount,
                            onGroupsTap: { showGroups = true },
                            onConnectionsTap: { showConnections = true }
                        )
                        Divider()
                        StartStopButton()
                    }
                    .padding(.horizontal)
                }
        } else {
            baseTabView
        }
    }

    var body: some View {
        if ApplicationLibrary.inPreview {
            mainBody.preferredColorScheme(.dark)
        } else {
            mainBody
        }
    }

    @ViewBuilder
    private var baseTabView: some View {
        TabView(selection: $selection) {
            ForEach(NavigationPage.allCases, id: \.self) { page in
                NavigationStackCompat {
                    page.contentView
                        .navigationTitle(page.title)
                }
                .tag(page)
                .tabItem { page.label }
            }
        }
    }

    private var mainBody: some View {
        Group {
            if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                tabViewContent
                    .onAppear {
                        updateButtonVisibility()
                    }
                    .onReceive(environments.commandClient.$groups) { _ in
                        updateButtonVisibility()
                    }
                    .onReceive(environments.commandClient.$connections) { _ in
                        updateButtonVisibility()
                    }
                    .onReceive(environments.commandClient.$hasAnyConnection) { _ in
                        updateButtonVisibility()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
                        updateButtonVisibility()
                    }
                    .onReceive(environments.$extensionProfile) { _ in
                        updateButtonVisibility()
                    }
                    .onReceive(environments.$emptyProfiles) { _ in
                        updateButtonVisibility()
                    }
                    .sheet(isPresented: $showGroups) {
                        GroupsSheetContent()
                    }
                    .sheet(isPresented: $showConnections) {
                        ConnectionsSheetContent()
                    }
            } else {
                baseTabView
            }
        }
        .onAppear {
            environments.postReload()
        }
        .alert($alert)
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                environments.postReload()
            }
        }
        .onChangeCompat(of: selection) { newValue in
            if newValue == .logs {
                environments.connect()
            }
        }
        .environment(\.selection, $selection)
        .environment(\.importProfile, $importProfile)
        .environment(\.importRemoteProfile, $importRemoteProfile)
        .environment(\.profileEditor, profileEditor)
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL(perform: openURL)
    }

    private func updateButtonVisibility() {
        buttonState.update(
            profile: environments.extensionProfile,
            commandClient: environments.commandClient
        )
    }

    private struct StatusText: View {
        @ObservedObject var profile: ExtensionProfile

        var body: some View {
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }

        private var statusText: String {
            switch profile.status {
            case .invalid:
                return String(localized: "Invalid")
            case .disconnected:
                return String(localized: "Stopped")
            case .connecting:
                return String(localized: "Starting")
            case .connected:
                return String(localized: "Started")
            case .reasserting:
                return String(localized: "Reasserting")
            case .disconnecting:
                return String(localized: "Stopping")
            @unknown default:
                return String(localized: "Unknown")
            }
        }
    }

    private func openURL(url: URL) {
        if url.host == "import-remote-profile" {
            var error: NSError?
            importRemoteProfile = LibboxParseRemoteProfileImportLink(url.absoluteString, &error)
            if let error {
                alert = AlertState(error: error)
                return
            }
            if selection != .dashboard {
                selection = .dashboard
            }
        } else if url.pathExtension == "bpf" {
            do {
                _ = url.startAccessingSecurityScopedResource()
                importProfile = try .from(Data(contentsOf: url))
                url.stopAccessingSecurityScopedResource()
            } catch {
                alert = AlertState(error: error)
                return
            }
            if selection != .dashboard {
                selection = .dashboard
            }
        } else {
            alert = AlertState(errorMessage: String(localized: "Handled unknown URL \(url.absoluteString)"))
        }
    }
}
