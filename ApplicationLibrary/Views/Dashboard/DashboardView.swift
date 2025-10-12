import Libbox
import Library
import SwiftUI

@MainActor
public struct DashboardView: View {
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
        @StateObject private var viewModel = DashboardViewModel()
    #endif

    public init() {}
    public var body: some View {
        viewBuilder {
            #if os(macOS)
                if Variant.useSystemExtension {
                    viewBuilder {
                        if !viewModel.systemExtensionInstalled {
                            FormView {
                                InstallSystemExtensionButton {
                                    await viewModel.reload()
                                }
                            }
                        } else {
                            DashboardView0()
                        }
                    }.onAppear {
                        Task {
                            await viewModel.reload()
                        }
                    }
                } else {
                    DashboardView0()
                }
            #else
                DashboardView0()
            #endif
        }
        #if os(macOS)
        .onChangeCompat(of: controlActiveState) { newValue in
            if newValue != .inactive {
                if Variant.useSystemExtension {
                    if !viewModel.isLoading {
                        Task {
                            await viewModel.reload()
                        }
                    }
                }
            }
        }
        #endif
    }

    struct DashboardView0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments

        var body: some View {
            if ApplicationLibrary.inPreview {
                ActiveDashboardView()
            } else if environments.extensionProfileLoading {
                ProgressView()
            } else if let profile = environments.extensionProfile {
                DashboardView1().environmentObject(profile)
            } else {
                FormView {
                    InstallProfileButton {
                        await environments.reload()
                    }
                }
            }
        }
    }

    struct DashboardView1: View {
        @Environment(\.openURL) var openURL
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var profile: ExtensionProfile
        @StateObject private var viewModel = DashboardViewModel()

        var body: some View {
            VStack {
                ActiveDashboardView()
            }
            .alertBinding($viewModel.alert)
            .onAppear {
                viewModel.setOpenURL { url in
                    openURL(url)
                }
            }
            .onChangeCompat(of: profile.status) { newValue in
                viewModel.handleStatusChange(newValue, profile: profile)
            }
        }
    }
}
