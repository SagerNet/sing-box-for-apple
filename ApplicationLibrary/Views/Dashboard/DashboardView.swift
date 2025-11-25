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
    @StateObject private var coordinator = DashboardCoordinator()
    @State private var importRemoteProfileRequest: NewProfileView.ImportRequest?

    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #endif

    public init() {}

    public var body: some View {
        content
            .onAppear {
                coordinator.setOpenURL { openURL($0) }
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
            .sheet(item: $importRemoteProfileRequest) { request in
                importRemoteProfileSheet(for: request)
            }
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
            coordinator.alert = Alert(
                title: Text("Import Profile"),
                message: Text("Are you sure to import profile \(profile.name)?"),
                primaryButton: .default(Text("Import")) {
                    Task {
                        do {
                            try await profile.importProfile()
                        } catch {
                            coordinator.alert = Alert(error)
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
            coordinator.alert = Alert(
                title: Text("Import Remote Profile"),
                message: Text("Are you sure to import remote profile \(remoteProfile.name)? You will connect to \(remoteProfile.host) to download the configuration."),
                primaryButton: .default(Text("Import")) {
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
        }) {
            NewProfileView(request)
                .environmentObject(environments)
        }
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
            ActiveDashboardView(externalCardConfigurationVersion: cardConfigurationVersion)
        } else if environments.extensionProfileLoading {
            ProgressView()
        } else if let profile = environments.extensionProfile {
            ActiveDashboardView(externalCardConfigurationVersion: cardConfigurationVersion)
                .environmentObject(profile)
                .alertBinding($coordinator.alert)
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
}
