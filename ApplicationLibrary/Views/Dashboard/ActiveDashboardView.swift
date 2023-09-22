import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct ActiveDashboardView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.selection) private var parentSelection
    @EnvironmentObject private var profile: ExtensionProfile
    @State private var isLoading = true
    @State private var profileList: [Profile] = []
    @State private var selectedProfileID: Int64!
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
                        ForEach(DashboardPage.allCases) { page in
                            page.contentView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
                                .tag(page)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                } else {
                    OverviewView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
                }
            #elseif os(macOS)
                OverviewView($profileList, $selectedProfileID, $systemProxyAvailable, $systemProxyEnabled)
            #endif
        }
        #if os(iOS) || os(tvOS)
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                Task {
                    await doReload()
                }
            }
        }
        .onChangeCompat(of: parentSelection.wrappedValue) { newValue in
            if newValue == .dashboard {
                Task {
                    await doReload()
                }
            }
        }
        #endif
        .alertBinding($alert)
    }

    private func doReload() async {
        defer {
            isLoading = false
        }
        if ApplicationLibrary.inPreview {
            profileList = [
                Profile(id: 0, name: "profile local", type: .local, path: ""),
                Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0)),
            ]
            systemProxyAvailable = true
            systemProxyEnabled = true
            selectedProfileID = 0

        } else {
            do {
                profileList = try await ProfileManager.list()
                if profileList.isEmpty {
                    return
                }
                selectedProfileID = await SharedPreferences.selectedProfileID.get()
                if profileList.filter({ profile in
                    profile.id == selectedProfileID
                })
                .isEmpty {
                    selectedProfileID = profileList[0].id!
                    await SharedPreferences.selectedProfileID.set(selectedProfileID)
                }

            } catch {
                alert = Alert(error)
            }
        }
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
