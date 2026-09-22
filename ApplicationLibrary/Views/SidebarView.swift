import Library
import SwiftUI

#if !os(tvOS)
    private extension Binding where Value == NavigationPage {
        var optionalSelection: Binding<NavigationPage?> {
            Binding<NavigationPage?>(
                get: { wrappedValue },
                set: { newValue in
                    if let newValue {
                        wrappedValue = newValue
                    }
                }
            )
        }
    }

    @available(iOS 16.0, macOS 13.0, *)
    private struct SidebarContentView: View {
        @Binding var selection: NavigationPage
        @Binding var localSelection: NavigationPage
        @ObservedObject var profile: ExtensionProfile
        @EnvironmentObject private var sendManager: TaildropSendManager
        var environments: ExtensionEnvironments

        private var hasGroups: Bool {
            Variant.screenshotMode || environments.commandClient.groups?.isEmpty == false
        }

        var body: some View {
            List(selection: $localSelection.optionalSelection) {
                if profile.status.isConnectedStrict {
                    NavigationPage.dashboard.label.tag(NavigationPage.dashboard)
                    if hasGroups {
                        NavigationPage.groups.label.tag(NavigationPage.groups)
                    }
                    NavigationPage.connections.label.tag(NavigationPage.connections)
                    ForEach(NavigationPage.sidebarDefaultPages, id: \.self) { it in
                        it.label
                            .badge(it == .tools ? environments.toolsBadgeCount + sendManager.failedSessionCount : 0)
                    }
                } else {
                    ForEach(NavigationPage.allCases.filter { $0.visible(profile) }, id: \.self) { it in
                        it.label
                            .badge(it == .tools ? environments.toolsBadgeCount + sendManager.failedSessionCount : 0)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .onAppear {
                localSelection = selection
            }
            .onChangeCompat(of: selection) { newValue in
                if localSelection != newValue {
                    localSelection = newValue
                }
            }
            .onChangeCompat(of: localSelection) { newValue in
                if selection != newValue {
                    Task { @MainActor in
                        selection = newValue
                    }
                }
            }
            .onChangeCompat(of: profile.status) {
                if !localSelection.visible(profile) {
                    Task { @MainActor in
                        localSelection = .dashboard
                    }
                }
            }
            .onReceive(environments.commandClient.$groups) { groups in
                if localSelection == .groups, groups?.isEmpty != false {
                    Task { @MainActor in
                        localSelection = .dashboard
                    }
                }
            }
        }
    }

    @available(iOS 16.0, macOS 13.0, *)
    private struct RemoteSidebarContentView: View {
        @Binding var selection: NavigationPage
        @Binding var localSelection: NavigationPage
        @ObservedObject var environments: ExtensionEnvironments
        @EnvironmentObject private var sendManager: TaildropSendManager
        @State private var hasGroups = false

        var body: some View {
            List(selection: $localSelection.optionalSelection) {
                NavigationPage.dashboard.label.tag(NavigationPage.dashboard)
                if hasGroups {
                    NavigationPage.groups.label.tag(NavigationPage.groups)
                }
                NavigationPage.connections.label.tag(NavigationPage.connections)
                ForEach(NavigationPage.sidebarDefaultPages, id: \.self) { it in
                    it.label
                        .badge(it == .tools ? environments.toolsBadgeCount + sendManager.failedSessionCount : 0)
                }
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .onAppear {
                localSelection = selection
                hasGroups = environments.commandClient.groups?.isEmpty == false
            }
            .onChangeCompat(of: selection) { newValue in
                if localSelection != newValue {
                    localSelection = newValue
                }
            }
            .onChangeCompat(of: localSelection) { newValue in
                if selection != newValue {
                    Task { @MainActor in
                        selection = newValue
                    }
                }
            }
            .onReceive(environments.commandClient.$groups) { groups in
                hasGroups = groups?.isEmpty == false
                if localSelection == .groups, groups?.isEmpty != false {
                    Task { @MainActor in
                        localSelection = .dashboard
                    }
                }
            }
            .onDisappear {
                if localSelection == .groups || localSelection == .connections {
                    Task { @MainActor in
                        localSelection = .dashboard
                    }
                }
            }
        }
    }

    @available(iOS 16.0, macOS 13.0, *)
    public struct SidebarView: View {
        @Binding var selection: NavigationPage
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var sendManager: TaildropSendManager
        @State private var localSelection: NavigationPage = .dashboard

        public init(selection: Binding<NavigationPage>) {
            _selection = selection
        }

        public var body: some View {
            if environments.remoteServer != nil {
                remoteContent
            } else if environments.extensionProfileLoading {
                ProgressView()
            } else if let profile = environments.extensionProfile {
                SidebarContentView(
                    selection: $selection,
                    localSelection: $localSelection,
                    profile: profile,
                    environments: environments
                )
            } else {
                disconnectedContent
            }
        }

        private var remoteContent: some View {
            RemoteSidebarContentView(
                selection: $selection,
                localSelection: $localSelection,
                environments: environments
            )
        }

        private var disconnectedContent: some View {
            List(selection: $localSelection.optionalSelection) {
                ForEach(NavigationPage.allCases.filter { $0.visible(nil) }, id: \.self) { it in
                    it.label
                        .badge(it == .tools ? environments.toolsBadgeCount + sendManager.failedSessionCount : 0)
                }
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .onAppear {
                localSelection = selection
            }
            .onChangeCompat(of: selection) { newValue in
                if localSelection != newValue {
                    localSelection = newValue
                }
            }
            .onChangeCompat(of: localSelection) { newValue in
                if selection != newValue {
                    Task { @MainActor in
                        selection = newValue
                    }
                }
            }
        }
    }
#endif
