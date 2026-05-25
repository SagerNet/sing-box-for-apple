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
    @State private var initializedTabs: Set<NavigationPage> = []

    private let profileEditor: (Binding<String>, Bool) -> AnyView = { text, isEditable in
        AnyView(ProfileEditorWrapperView(text: text, isEditable: isEditable))
    }

    private let ghosttyConfigEditor: (Binding<String>) -> AnyView = { text in
        AnyView(GhosttyConfigEditorWrapperView(text: text))
    }

    private var tabViewContent: some View {
        TabView(selection: $selection) {
            ForEach(NavigationPage.allCases, id: \.self) { page in
                NavigationStackCompat {
                    tabContent(for: page)
                }
                .tag(page)
                .tabItem { page.label }
                .badge(page == .tools ? environments.totalUnreadReportCount : 0)
            }
        }
    }

    var body: some View {
        if Variant.screenshotMode {
            mainBody.preferredColorScheme(.dark)
        } else {
            mainBody
        }
    }

    @ViewBuilder
    private func tabContent(for page: NavigationPage) -> some View {
        let content = page.contentView
            .navigationTitle(page.title)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                accessoryInset
                    .transaction { transaction in
                        if !initializedTabs.contains(page) {
                            transaction.disablesAnimations = true
                        }
                    }
            }
            .onAppear {
                if !initializedTabs.contains(page) {
                    DispatchQueue.main.async {
                        initializedTabs.insert(page)
                    }
                }
            }
        if page == .logs {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }

    @ViewBuilder
    private var accessoryInset: some View {
        if let profile = environments.extensionProfile, !environments.extensionProfileLoading, !environments.emptyProfiles {
            AccessoryInset(profile: profile) {
                statusBarPill
            } fab: {
                fabInset
            }
        }
    }

    private var fabInset: some View {
        HStack {
            Spacer()
            FABStartButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var statusBarPill: some View {
        bottomAccessoryContent
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .modifier(AccessoryPillBackgroundModifier(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    private struct AccessoryPillBackgroundModifier: ViewModifier {
        let cornerRadius: CGFloat
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content.background(.bar, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private var bottomAccessoryContent: some View {
        HStack(spacing: 12) {
            if let profile = environments.extensionProfile {
                StatusText(profile: profile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            StartStopButton(showsRuntimeDuration: true)
        }
        .padding(.horizontal)
        .tint(.primary)
        .buttonStyle(BarItemButtonStyle())
    }

    private struct BarItemButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.5 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    private var mainBody: some View {
        Group {
            tabViewContent
                .onAppear {
                    updateButtonVisibility()
                }
                .onReceive(environments.commandClient.$groups) { _ in
                    Task { @MainActor in updateButtonVisibility() }
                }
                .onReceive(environments.commandClient.$connections) { _ in
                    Task { @MainActor in updateButtonVisibility() }
                }
                .onReceive(environments.commandClient.$hasAnyConnection) { _ in
                    Task { @MainActor in updateButtonVisibility() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
                    Task { @MainActor in updateButtonVisibility() }
                }
                .onReceive(environments.$extensionProfile) { _ in
                    Task { @MainActor in updateButtonVisibility() }
                }
                .onReceive(environments.$emptyProfiles) { _ in
                    Task { @MainActor in updateButtonVisibility() }
                }
                .sheet(isPresented: $showGroups) {
                    GroupsSheetContent()
                }
                .sheet(isPresented: $showConnections) {
                    ConnectionsSheetContent()
                }
        }
        .onAppear {
            environments.postReload()
        }
        .alert($alert)
        .globalChecks()
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
        .onReceive(NotificationCenter.default.publisher(for: .reportReceived)) { _ in
            Task {
                await environments.crashReportManager.refresh()
                await environments.oomReportManager.refresh()
                selection = .tools
            }
        }
        .environment(\.selection, $selection)
        .environment(\.importProfile, $importProfile)
        .environment(\.importRemoteProfile, $importRemoteProfile)
        .environment(\.profileEditor, profileEditor)
        .environment(\.ghosttyConfigEditor, ghosttyConfigEditor)
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL(perform: openURL)
    }

    private func updateButtonVisibility() {
        buttonState.update(
            profile: environments.extensionProfile,
            commandClient: environments.commandClient
        )
    }

    private struct AccessoryInset<StatusBar: View, FAB: View>: View {
        @ObservedObject var profile: ExtensionProfile
        @ViewBuilder let statusBar: () -> StatusBar
        @ViewBuilder let fab: () -> FAB

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                if profile.status == .disconnected {
                    fab()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    statusBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: profile.status)
        }
    }

    private struct FABStartButton: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @State private var alert: AlertState?

        var body: some View {
            Button {
                guard let profile = environments.extensionProfile else { return }
                Task {
                    do {
                        try await profile.start()
                    } catch {
                        alert = AlertState(action: "start service", error: error)
                    }
                }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .modifier(FABBackgroundModifier())
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(environments.extensionProfile == nil || environments.emptyProfiles)
            .alert($alert)
        }

        private struct FABBackgroundModifier: ViewModifier {
            func body(content: Content) -> some View {
                if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                    content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    content.background(.bar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private struct StatusText: View {
        @ObservedObject var profile: ExtensionProfile

        var body: some View {
            statusText
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }

        private var statusText: Text {
            switch profile.status {
            case .disconnected:
                return Text("Stopped")
            case .connecting:
                return Text("Starting")
            case .connected:
                return Text("Started")
            case .reasserting:
                return Text("Reasserting")
            case .disconnecting:
                return Text("Stopping")
            default:
                return Text("Unknown")
                    .foregroundColor(.red)
            }
        }
    }

    private func openURL(url: URL) {
        if url.host == "import-remote-profile" {
            var error: NSError?
            importRemoteProfile = LibboxParseRemoteProfileImportLink(url.absoluteString, &error)
            if let error {
                alert = AlertState(action: "parse remote profile import link", error: error)
            }
        } else if url.pathExtension == "bpf" {
            do {
                importProfile = try url.withSecurityScopedAccess {
                    try .from(Data(contentsOf: url))
                }
            } catch {
                alert = AlertState(action: "import profile from URL", error: error)
            }
        } else {
            alert = AlertState(errorMessage: String(localized: "Handled unknown URL \(url.absoluteString)"))
        }
    }
}
