import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct ActiveDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @StateObject private var coordinator = DashboardCoordinator()
    @State private var cardConfigurationVersion = 0
    #if os(iOS) || os(tvOS)
        @State private var showCardManagement = false
    #endif

    private let externalCardConfigurationVersion: Int?

    public init(externalCardConfigurationVersion: Int? = nil) {
        self.externalCardConfigurationVersion = externalCardConfigurationVersion
    }

    public var body: some View {
        if coordinator.isLoading {
            ProgressView()
                .onAppear {
                    coordinator.onEmptyProfilesChange = { environments.emptyProfiles = $0 }
                    Task { await coordinator.reload() }
                }
        } else {
            content
                .onAppear {
                    guard !ApplicationLibrary.inPreview else { return }
                    Task { await coordinator.reloadSystemProxy() }
                }
                .onChangeCompat(of: profile.status) { status in
                    guard !ApplicationLibrary.inPreview, status == .connected else { return }
                    Task { await coordinator.reloadSystemProxy() }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack {
            #if os(iOS) || os(tvOS)
                if ApplicationLibrary.inPreview || profile.status.isConnectedStrict {
                    pageSelector
                    pageContent
                } else {
                    overviewPage
                }
            #else
                overviewPage
            #endif
        }
        #if os(iOS) || os(tvOS)
        .toolbar { toolbar }
        #endif
        .onAppear {
            if ApplicationLibrary.inPreview {
                environments.commandClient.connect()
            } else {
                environments.connect()
            }
        }
        .onChangeCompat(of: scenePhase) { phase in
            guard phase == .active else { return }
            environments.connect()
        }
        .onChangeCompat(of: profile.status) { status in
            guard status.isConnected else { return }
            environments.connect()
        }
        .onReceive(environments.profileUpdate) { _ in
            Task { await coordinator.reload() }
        }
        .onReceive(environments.selectedProfileUpdate) { _ in
            Task {
                await coordinator.updateSelectedProfile()
                if profile.status.isConnected {
                    await coordinator.reloadSystemProxy()
                }
            }
        }
        .alertBinding($coordinator.alert)
    }

    #if os(iOS) || os(tvOS)
        @ViewBuilder
        private var pageSelector: some View {
            Picker("Page", selection: $coordinator.selection) {
                ForEach(DashboardPage.enabledCases()) { page in
                    page.label
                }
            }
            .pickerStyle(.segmented)
            #if os(iOS)
                .padding([.leading, .trailing])
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        @ViewBuilder
        private var pageContent: some View {
            TabView(selection: $coordinator.selection) {
                ForEach(DashboardPage.enabledCases()) { page in
                    page.contentView(
                        $coordinator.profileList,
                        $coordinator.selectedProfileID,
                        $coordinator.systemProxyAvailable,
                        $coordinator.systemProxyEnabled,
                        externalCardConfigurationVersion ?? cardConfigurationVersion
                    )
                    .tag(page)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    #endif

    @ViewBuilder
    private var overviewPage: some View {
        OverviewView(
            $coordinator.profileList,
            $coordinator.selectedProfileID,
            $coordinator.systemProxyAvailable,
            $coordinator.systemProxyEnabled,
            cardConfigurationVersion: externalCardConfigurationVersion ?? cardConfigurationVersion
        )
    }

    #if os(iOS) || os(tvOS)
        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                if coordinator.selection == .overview {
                    if #available(iOS 16.0, tvOS 17.0, *) {
                        cardManagementButton
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                    EmptyView()
                } else {
                    StartStopButton()
                }
            }
        }
    #endif

    #if os(iOS) || os(tvOS)
        @available(iOS 16.0, tvOS 17.0, *)
        @ViewBuilder
        private var cardManagementButton: some View {
            Menu {
                Button {
                    showCardManagement = true
                } label: {
                    Label("Dashboard Items", systemImage: "square.grid.2x2")
                }
            } label: {
                Label("Others", systemImage: "ellipsis.circle")
            }
            .sheet(isPresented: $showCardManagement) {
                CardManagementSheet(configurationVersion: $cardConfigurationVersion)
                    .presentationDetents([.medium, .large])
            }
        }
    #endif
}
