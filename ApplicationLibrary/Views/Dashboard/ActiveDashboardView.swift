import Foundation
import Libbox
import Library
import SwiftUI

@MainActor public struct ActiveDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @ObservedObject private var coordinator: DashboardViewModel
    @StateObject private var cardConfiguration = DashboardCardConfiguration()
    #if os(iOS) || os(tvOS)
        @State private var showCardManagement = false
    #endif
    #if os(tvOS)
        @State private var showGroups = false
        @State private var showConnections = false
        @State private var buttonState = ButtonVisibilityState()
    #endif
    #if os(macOS)
        @Environment(\.cardConfigurationVersion) private var cardConfigurationVersion
    #endif

    public init(coordinator: DashboardViewModel) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
    }

    public var body: some View {
        viewContent
    }

    @ViewBuilder private var viewContent: some View {
        if coordinator.isLoading {
            ProgressView()
            #if os(iOS) || os(tvOS)
                .onAppear {
                    Task {
                        await coordinator.reload()
                    }
                }
            #endif
        } else {
            content.onAppear {
                guard !Variant.screenshotMode, profile.status.isConnected else {
                    return
                }
                Task {
                    await coordinator.reloadSystemProxy()
                }
            }.onChangeCompat(of: profile.status) { status in
                guard !Variant.screenshotMode, status == .connected else {
                    return
                }
                Task {
                    await coordinator.reloadSystemProxy()
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            overviewPage
        }
        #if os(iOS) || os(tvOS)
        .toolbar {
            toolbar
        }
            #if os(tvOS)
        .navigationDestination(isPresented: $showGroups) {
            GroupListView()
                .navigationTitle("Groups")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }
        .navigationDestination(isPresented: $showConnections) {
            ConnectionListView()
                .navigationTitle("Connections")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }
        .navigationDestination(isPresented: $showCardManagement) {
            CardManagementView(onDisappear: {
                Task { await cardConfiguration.reload() }
            })
            .navigationTitle("Dashboard Items")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    BackButton()
                }
            }
        }
            #else
        .sheet(isPresented: $showCardManagement, onDismiss: {
                        Task { await cardConfiguration.reload() }
                    }, content: {
                        if #available(iOS 16.0, *) {
                            CardManagementSheet().presentationDetents([.large]).presentationDragIndicator(.visible)
                        } else {
                            CardManagementSheet()
                        }
                    })
            #endif
        #endif
        .onAppear {
                environments.connect()
            }.onChangeCompat(of: scenePhase) { phase in
                guard phase == .active else {
                    return
                }
                environments.connect()
            }.onChangeCompat(of: profile.status) { status in
                guard status.isConnected else {
                    return
                }
                environments.connect()
            }.onReceive(environments.profileUpdate) { _ in
                Task {
                    await coordinator.reload()
                }
            }.onReceive(environments.selectedProfileUpdate) { _ in
                Task {
                    await coordinator.updateSelectedProfile()
                    if profile.status.isConnected {
                        await coordinator.reloadSystemProxy()
                    }
                }
            }
        #if os(tvOS)
            .onReceive(environments.commandClient.$groups) { _ in
                Task { @MainActor in
                    updateButtonVisibility()
                }
            }.onReceive(profile.$status) { _ in
                Task { @MainActor in
                    updateButtonVisibility()
                }
            }.onAppear {
                updateButtonVisibility()
            }
        #endif
        #if os(macOS)
            .onChangeCompat(of: cardConfigurationVersion) { _ in
                Task { await cardConfiguration.reload() }
        }
        #endif
    }

    @ViewBuilder private var overviewPage: some View {
        OverviewView(
            $coordinator.profileList,
            $coordinator.selectedProfileID,
            $coordinator.systemProxyAvailable,
            $coordinator.systemProxyEnabled,
            cardConfiguration: cardConfiguration
        )
    }

    #if os(tvOS)
        private func updateButtonVisibility() {
            buttonState.update(profile: profile, commandClient: environments.commandClient)
        }
    #endif

    #if os(iOS) || os(tvOS)
        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            #if os(tvOS)
                ToolbarItemGroup(placement: .topBarLeading) {
                    navigationButtons
                }
            #endif
            ToolbarItemGroup(placement: .topBarTrailing) {
                if #available(iOS 16.0, tvOS 17.0, *) {
                    cardManagementButton
                }
                #if os(tvOS)
                    StartStopButton()
                #endif
            }
        }

        #if os(tvOS)
            private var navigationButtons: some View {
                NavigationButtonsView(
                    showGroupsButton: buttonState.showGroupsButton,
                    showConnectionsButton: buttonState.showConnectionsButton,
                    groupsCount: buttonState.groupsCount,
                    connectionsCount: buttonState.connectionsCount,
                    onGroupsTap: {
                        showGroups = true
                    },
                    onConnectionsTap: {
                        showConnections = true
                    }
                )
            }
        #endif
    #endif

    #if os(iOS) || os(tvOS)
        @available(iOS 16.0, *) @ViewBuilder private var cardManagementButton: some View {
            #if os(iOS)
                Menu {
                    Button {
                        showCardManagement = true
                    } label: {
                        Label("Dashboard Items", systemImage: "square.grid.2x2")
                    }
                } label: {
                    Label("Others", systemImage: "line.3.horizontal.circle")
                }
            #elseif os(tvOS)
                Button {
                    showCardManagement = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
            #endif
        }
    #endif
}
