import Foundation
import Libbox
import Library
import SwiftUI

@MainActor public struct ActiveDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @ObservedObject private var coordinator: DashboardViewModel
    @State private var cardConfigurationVersion = 0
    #if os(iOS) || os(tvOS)
        @State private var showCardManagement = false
        @State private var showGroups = false
        @State private var showConnections = false
        @State private var buttonState = ButtonVisibilityState()
    #endif

    private let externalCardConfigurationVersion: Int?

    public init(coordinator: DashboardViewModel, externalCardConfigurationVersion: Int? = nil) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        self.externalCardConfigurationVersion = externalCardConfigurationVersion
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
                guard !ApplicationLibrary.inPreview, profile.status.isConnected else {
                    return
                }
                Task {
                    await coordinator.reloadSystemProxy()
                }
            }.onChangeCompat(of: profile.status) { status in
                guard !ApplicationLibrary.inPreview, status == .connected else {
                    return
                }
                Task {
                    await coordinator.reloadSystemProxy()
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        overviewPage
        #if os(iOS) || os(tvOS)
        .toolbar {
            toolbar
        }.sheet(isPresented: $showGroups) {
            groupsSheetContent
        }.sheet(isPresented: $showConnections) {
            connectionsSheetContent
        }.sheet(isPresented: $showCardManagement, onDismiss: {
            cardConfigurationVersion += 1
        }, content: {
            if #available(iOS 16.0, tvOS 17.0, *) {
                CardManagementSheet().presentationDetents([.large]).presentationDragIndicator(.visible)
            } else {
                CardManagementSheet()
            }
        })
        #endif
        .onAppear {
            if ApplicationLibrary.inPreview {
                environments.commandClient.connect()
            } else {
                environments.connect()
            }
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
        #if os(iOS) || os(tvOS)
        .onReceive(environments.commandClient.$groups) { _ in
            updateButtonVisibility()
        }.onReceive(environments.commandClient.$connections) { _ in
            updateButtonVisibility()
        }.onReceive(profile.$status) { _ in
            updateButtonVisibility()
        }.onAppear {
            updateButtonVisibility()
        }
        #endif
    }

    @ViewBuilder private var overviewPage: some View {
        OverviewView(
            $coordinator.profileList,
            $coordinator.selectedProfileID,
            $coordinator.systemProxyAvailable,
            $coordinator.systemProxyEnabled,
            cardConfigurationVersion: externalCardConfigurationVersion ?? cardConfigurationVersion
        )
    }

    #if os(iOS) || os(tvOS)
        private func updateButtonVisibility() {
            buttonState.update(profile: profile, commandClient: environments.commandClient, requireAnyConnection: true)
        }

        #if os(iOS)
            private var isTabViewBottomAccessoryAvailable: Bool {
                if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                    return true
                }
                return false
            }
        #endif

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            #if os(tvOS)
                ToolbarItem(placement: .topBarLeading) {
                    navigationButtons
                }
            #endif
            ToolbarItemGroup(placement: .topBarTrailing) {
                if #available(iOS 16.0, tvOS 17.0, *) {
                    cardManagementButton
                }
                #if os(tvOS)
                    StartStopButton()
                #else
                    if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                    } else {
                        StartStopButton()
                    }
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
        private var groupsSheetContent: some View {
            GroupsSheetContent()
        }

        private var connectionsSheetContent: some View {
            ConnectionsSheetContent()
        }

        @available(iOS 16.0, *) @ViewBuilder private var cardManagementButton: some View {
            #if os(iOS)
                Menu {
                    if !isTabViewBottomAccessoryAvailable {
                        if buttonState.showGroupsButton {
                            Button {
                                showGroups = true
                            } label: {
                                Label("Groups (\(buttonState.groupsCount))", systemImage: "rectangle.3.group.fill")
                            }
                        }
                        if buttonState.showConnectionsButton {
                            Button {
                                showConnections = true
                            } label: {
                                Label("Connections (\(buttonState.connectionsCount))", systemImage: "list.bullet.rectangle.portrait.fill")
                            }
                        }
                        if buttonState.showGroupsButton || buttonState.showConnectionsButton {
                            Divider()
                        }
                    }
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
                    Image(systemName: "line.3.horizontal.circle")
                }
            #endif
        }
    #endif
}
