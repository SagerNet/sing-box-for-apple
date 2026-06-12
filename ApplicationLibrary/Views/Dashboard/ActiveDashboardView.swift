import Foundation
import Libbox
import Library
import SwiftUI

@MainActor public struct ActiveDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @ObservedObject private var coordinator: DashboardViewModel
    @ObservedObject private var cardConfiguration: DashboardCardConfiguration
    #if os(tvOS)
        @State private var showCardManagement = false
        @State private var showGroups = false
        @State private var showConnections = false
        @State private var buttonState = ButtonVisibilityState()
    #endif

    public init(coordinator: DashboardViewModel, cardConfiguration: DashboardCardConfiguration) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _cardConfiguration = ObservedObject(wrappedValue: cardConfiguration)
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
        #if os(tvOS)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                navigationButtons
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showCardManagement = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                StartStopButton()
            }
        }
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
    }

    private var overviewPage: some View {
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
}
