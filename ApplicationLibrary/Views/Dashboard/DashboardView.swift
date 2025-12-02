import Libbox
import Library
import SwiftUI

@MainActor
public struct DashboardView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.cardConfigurationVersion) private var cardConfigurationVersion
    @Environment(\.importProfile) private var importProfile
    @Environment(\.importRemoteProfile) private var importRemoteProfile
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var coordinator = DashboardViewModel()
    @State private var importRemoteProfileRequest: NewProfileView.ImportRequest?

    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #endif

    public init() {}

    public var body: some View {
        content
            .onAppear {
                coordinator.setOpenURL { openURL($0) }
                coordinator.setEnvironments(environments)
                #if os(macOS)
                    Task { await coordinator.reload() }
                #endif
                handleImportProfile()
                handleImportRemoteProfile()
            }
            .onChangeCompat(of: importProfile.wrappedValue) { _ in
                handleImportProfile()
            }
            .onChangeCompat(of: importRemoteProfile.wrappedValue) { _ in
                handleImportRemoteProfile()
            }
            #if os(tvOS)
            .navigationDestination(item: $importRemoteProfileRequest) { request in
                NewProfileView(request)
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
            .sheet(item: $importRemoteProfileRequest) { request in
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

    private func handleImportProfile() {
        if let profile = importProfile.wrappedValue {
            importProfile.wrappedValue = nil
            coordinator.alert = AlertState(
                title: String(localized: "Import Profile"),
                message: String(localized: "Are you sure to import profile \(profile.name)?"),
                primaryButton: .default(String(localized: "Import")) {
                    Task {
                        do {
                            try await profile.importProfile()
                        } catch {
                            coordinator.alert = AlertState(error: error)
                            return
                        }
                        environments.profileUpdate.send()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func handleImportRemoteProfile() {
        if let remoteProfile = importRemoteProfile.wrappedValue {
            importRemoteProfile.wrappedValue = nil
            coordinator.alert = AlertState(
                title: String(localized: "Import Remote Profile"),
                message: String(localized: "Are you sure to import remote profile \(remoteProfile.name)? You will connect to \(remoteProfile.host) to download the configuration."),
                primaryButton: .default(String(localized: "Import")) {
                    importRemoteProfileRequest = .init(name: remoteProfile.name, url: remoteProfile.url)
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func importRemoteProfileSheet(for request: NewProfileView.ImportRequest) -> some View {
        NavigationSheet(title: "Import Profile", onDismiss: {
            environments.profileUpdate.send()
        }, content: {
            NewProfileView(request)
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
        if ApplicationLibrary.inPreview {
            activeDashboardView
        } else if environments.extensionProfileLoading {
            ProgressView()
        } else if let profile = environments.extensionProfile {
            activeDashboardView
                .environmentObject(profile)
                .alert($coordinator.alert)
                .onChangeCompat(of: profile.status) { status in
                    coordinator.handleStatusChange(status, profile: profile)
                }
        } else {
            FormView {
                InstallProfileButton {
                    await environments.reload()
                }
            }
        }
    }

    @ViewBuilder
    private var activeDashboardView: some View {
        #if os(macOS)
            ActiveDashboardView(coordinator: coordinator, externalCardConfigurationVersion: cardConfigurationVersion)
        #else
            ActiveDashboardView(coordinator: coordinator)
        #endif
    }
}
