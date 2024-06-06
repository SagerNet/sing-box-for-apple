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
    @State private var isLoading = true
    @State private var profileList: [ProfilePreview] = []
    @State private var selectedProfileID: Int64 = 0
    @State private var alert: Alert?
    @State private var selection = DashboardPage.overview
    @State private var systemProxyAvailable = false
    @State private var systemProxyEnabled = false

    public init() {}
    public var body: some View {
        if isLoading {
            ProgressView().onAppear {
                Task {
                    await doReload()
                }
            }
        } else {
            if ApplicationLibrary.inPreview {
                body1
            } else {
                body1
                    .onAppear {
                        Task {
                            await doReloadSystemProxy()
                        }
                    }
                    .onChangeCompat(of: profile.status) { newStatus in
                        if newStatus == .connected {
                            Task {
                                await doReloadSystemProxy()
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
                    viewBuilder {
                        #if os(iOS)
                            if #available(iOS 16.0, *) {
                                content1
                            } else {
                                content0
                            }
                        #else
                            content0
                        #endif
                    }
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .onAppear {
                        UIScrollView.appearance().isScrollEnabled = false
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    OverviewView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
                }
            #elseif os(macOS)
                OverviewView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
            #endif
        }
        .onReceive(environments.profileUpdate) { _ in
            Task {
                await doReload()
            }
        }
        .onReceive(environments.selectedProfileUpdate) { _ in
            Task {
                selectedProfileID = await SharedPreferences.selectedProfileID.get()
                if profile.status.isConnected {
                    await doReloadSystemProxy()
                }
            }
        }
        .alertBinding($alert)
    }

    @ViewBuilder
    private var content0: some View {
        Picker("Page", selection: $selection) {
            ForEach(DashboardPage.allCases) { page in
                page.label
            }
        }
        .pickerStyle(.segmented)
        #if os(iOS)
            .padding([.leading, .trailing])
            .navigationBarTitleDisplayMode(.inline)
        #endif
        TabView(selection: $selection) {
            ForEach(DashboardPage.enabledCases) { page in
                page.contentView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
                    .tag(page)
            }
        }
    }

    @ViewBuilder
    private var content1: some View {
        TabView(selection: $selection) {
            ForEach(DashboardPage.enabledCases) { page in
                page.contentView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
                    .tag(page)
            }
        }
        .toolbar {
            ToolbarTitleMenu {
                Picker("Page", selection: $selection) {
                    ForEach(DashboardPage.allCases) { page in
                        page.label
                    }
                }
            }
        }
    }

    private func doReload() async {
        defer {
            isLoading = false
        }
        if ApplicationLibrary.inPreview {
            profileList = [
                ProfilePreview(Profile(id: 0, name: "profile local", type: .local, path: "")),
                ProfilePreview(Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0))),
            ]
            systemProxyAvailable = true
            systemProxyEnabled = true
            selectedProfileID = 0

        } else {
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
                if profileList.isEmpty {
                    return
                }
                selectedProfileID = await SharedPreferences.selectedProfileID.get()
                if profileList.filter({ profile in
                    profile.id == selectedProfileID
                })
                .isEmpty {
                    selectedProfileID = profileList[0].id
                    await SharedPreferences.selectedProfileID.set(selectedProfileID)
                }

            } catch {
                alert = Alert(error)
                return
            }
        }
        environments.emptyProfiles = profileList.isEmpty
    }

    private nonisolated func doReloadSystemProxy() async {
        do {
            let status = try LibboxNewStandaloneCommandClient()!.getSystemProxyStatus()
            await MainActor.run {
                systemProxyAvailable = status.available
                systemProxyEnabled = status.enabled
            }
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
