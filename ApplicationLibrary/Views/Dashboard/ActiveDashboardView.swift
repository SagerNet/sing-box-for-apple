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
        .environmentObject(viewModel.dashboardClient)
        .onAppear {
            if ApplicationLibrary.inPreview || profile.status.isConnected {
                viewModel.dashboardClient.connect()
            }
        }
        .onDisappear {
            viewModel.dashboardClient.disconnect()
        }
        .onChangeCompat(of: scenePhase) { newPhase in
            if newPhase == .active {
                if profile.status.isConnected {
                    viewModel.dashboardClient.connect()
                }
            } else {
                viewModel.dashboardClient.disconnect()
            }
        }
        .onChangeCompat(of: profile.status) { newStatus in
            if newStatus.isConnected {
                viewModel.dashboardClient.connect()
            } else {
                viewModel.dashboardClient.disconnect()
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
