import Libbox
import Library
import SwiftUI

@MainActor
public struct DashboardView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var coordinator = DashboardViewModel()

    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
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
        #endif
    }

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
        if environments.extensionProfileLoading {
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
        ActiveDashboardView(coordinator: coordinator)
    }
}
