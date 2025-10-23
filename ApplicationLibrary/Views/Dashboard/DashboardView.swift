import Libbox
import Library
import SwiftUI

@MainActor
public struct DashboardView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.cardConfigurationVersion) private var cardConfigurationVersion
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var coordinator = DashboardCoordinator()

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
            }
        #if os(macOS)
            .onChangeCompat(of: controlActiveState) { state in
                guard state != .inactive, Variant.useSystemExtension, !coordinator.isLoading else { return }
                Task { await coordinator.reload() }
            }
        #endif
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
