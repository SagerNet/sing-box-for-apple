import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct ActiveDashboardView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.selection) private var parentSelection
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @StateObject private var viewModel = ActiveDashboardViewModel()

    public init() {}
    public var body: some View {
        if viewModel.isLoading {
            ProgressView().onAppear {
                viewModel.onEmptyProfilesChange = { isEmpty in
                    environments.emptyProfiles = isEmpty
                }
                Task {
                    await viewModel.reload()
                }
            }
        } else {
            if ApplicationLibrary.inPreview {
                body1
            } else {
                body1
                    .onAppear {
                        Task {
                            await viewModel.reloadSystemProxy()
                        }
                    }
                    .onChangeCompat(of: profile.status) { newStatus in
                        if newStatus == .connected {
                            Task {
                                await viewModel.reloadSystemProxy()
                            }
                        }
                    }
            }
        }
    }

    private var body1: some View {
        VStack {
            #if os(iOS) || os(tvOS)
                if ApplicationLibrary.inPreview || profile.status.isConnectedStrict {
                    Picker("Page", selection: $viewModel.selection) {
                        ForEach(DashboardPage.enabledCases()) { page in
                            page.label
                        }
                    }
                    .pickerStyle(.segmented)
                    #if os(iOS)
                        .padding([.leading, .trailing])
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                    TabView(selection: $viewModel.selection) {
                        ForEach(DashboardPage.enabledCases()) { page in
                            page.contentView($viewModel.profileList, $viewModel.selectedProfileID, $viewModel.systemProxyAvailable, $viewModel.systemProxyEnabled)
                                .tag(page)
                        }
                    }
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    OverviewView($viewModel.profileList, $viewModel.selectedProfileID, $viewModel.systemProxyAvailable, $viewModel.systemProxyEnabled)
                }
            #elseif os(macOS)
                OverviewView($viewModel.profileList, $viewModel.selectedProfileID, $viewModel.systemProxyAvailable, $viewModel.systemProxyEnabled)
            #endif
        }
        #if os(iOS) || os(tvOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                StartStopButton()
            }
        }
        .modifier(DashboardMenuToolbarModifier(selection: viewModel.selection))
        #endif
        .onAppear {
            if ApplicationLibrary.inPreview {
                environments.commandClient.connect()
            } else {
                environments.connect()
            }
        }
        .onChangeCompat(of: scenePhase) { newPhase in
            if newPhase == .active {
                environments.connect()
            }
        }
        .onChangeCompat(of: profile.status) { newStatus in
            if newStatus.isConnected {
                environments.connect()
            }
        }
        .onReceive(environments.profileUpdate) { _ in
            Task {
                await viewModel.reload()
            }
        }
        .onReceive(environments.selectedProfileUpdate) { _ in
            Task {
                await viewModel.updateSelectedProfile()
                if profile.status.isConnected {
                    await viewModel.reloadSystemProxy()
                }
            }
        }
        .alertBinding($viewModel.alert)
    }
}

#if os(iOS) || os(tvOS)
    private struct DashboardMenuToolbarModifier: ViewModifier {
        let selection: DashboardPage

        func body(content: Content) -> some View {
            if #available(iOS 16.0, tvOS 17.0, *) {
                content.toolbar {
                    if selection == .overview {
                        ToolbarItem(placement: .topBarTrailing) {
                            DashboardMenu()
                        }
                    }
                }
            } else {
                content
            }
        }
    }
#endif
