import Libbox
import Library
import SwiftUI

@MainActor
public struct DashboardView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var coordinator = DashboardViewModel()
    @StateObject private var cardConfiguration = DashboardCardConfiguration()

    #if os(iOS)
        @State private var showCardManagement = false
        @State private var remoteServers: [RemoteServer] = []
    #endif

    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
        @Environment(\.cardConfigurationVersion) private var cardConfigurationVersion
    #endif

    public init() {}

    public var body: some View {
        content
            .alert($coordinator.alert)
            .onAppear {
                coordinator.setEnvironments(environments)
                #if os(macOS)
                    Task { await coordinator.reload() }
                #endif
            }
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    othersMenu
                }
            }
            .onAppear {
                Task { await reloadRemoteServers() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .remoteServersUpdated)) { _ in
                Task { await reloadRemoteServers() }
            }
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
        #if os(tvOS)
            .navigationDestination(item: $environments.pendingImportRemoteProfile) { request in
                NewProfileView(.init(name: request.name, url: request.url))
                    .environmentObject(environments)
                    .onDisappear {
                        environments.profileUpdate.send()
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
        }
        #else
        .sheet(item: $environments.pendingImportRemoteProfile) { request in
                    importRemoteProfileSheet(for: request)
                }
        #endif
        #if os(macOS)
            .onChangeCompat(of: controlActiveState) { state in
                guard state != .inactive, Variant.useSystemExtension, !coordinator.isLoading else { return }
                Task { await coordinator.reload() }
        }
        .onChangeCompat(of: cardConfigurationVersion) { _ in
            Task { await cardConfiguration.reload() }
        }
        #endif
    }

    #if os(iOS)
        private var othersMenu: some View {
            Menu {
                Button {
                    showCardManagement = true
                } label: {
                    Label("Dashboard Items", systemImage: "square.grid.2x2")
                }
                RemoteControlMenuItems(servers: remoteServers)
            } label: {
                Label("Others", systemImage: "line.3.horizontal.circle")
            }
        }

        private func reloadRemoteServers() async {
            remoteServers = await (try? RemoteServerManager.list()) ?? []
        }
    #endif

    private func importRemoteProfileSheet(for request: ImportRemoteProfileRequest) -> some View {
        NavigationSheet(title: "Import Profile", onDismiss: {
            environments.profileUpdate.send()
        }, content: {
            NewProfileView(.init(name: request.name, url: request.url))
                .environmentObject(environments)
        })
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
            if Variant.useSystemExtension, !coordinator.systemExtensionInstalled {
                FormView {
                    InstallSystemExtensionButton {
                        await coordinator.reload()
                    }
                }
            } else {
                mainContent
            }
        #else
            mainContent
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        if environments.remoteServer != nil {
            RemoteDashboardView(commandClient: environments.commandClient, cardConfiguration: cardConfiguration)
        } else if environments.extensionProfileLoading {
            ProgressView()
        } else if let profile = environments.extensionProfile {
            activeDashboardView
                .environmentObject(profile)
                .onChangeCompat(of: profile.status) { status in
                    #if os(macOS)
                        if Variant.useSystemExtension, status == .connected {
                            UserServiceEndpointPublisher.shared.refreshEndpointRegistration()
                            UserServiceEndpointPublisher.shared.checkExtensionRequirements()
                        }
                    #endif
                }
        } else {
            FormView {
                InstallProfileButton {
                    await environments.reload()
                }
            }
        }
    }

    private var activeDashboardView: some View {
        ActiveDashboardView(coordinator: coordinator, cardConfiguration: cardConfiguration)
    }
}
