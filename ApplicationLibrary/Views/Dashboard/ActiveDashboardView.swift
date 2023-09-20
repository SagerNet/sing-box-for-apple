import Foundation
import Libbox
import Library
import SwiftUI

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
                Task.detached {
                    await doReload()
                }
            }
        } else {
            if ApplicationLibrary.inPreview {
                body1
            } else {
                body1
                    .onChangeCompat(of: profile.status) { newStatus in
                        if newStatus == .connected {
                            Task.detached {
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
                Task.detached {
                    await doReload()
                }
            }
        }
        .onChangeCompat(of: parentSelection.wrappedValue) { newValue in
            if newValue == .dashboard {
                Task.detached {
                    await doReload()
                }
            }
        }
        #endif
        .alertBinding($alert)
    }

    private func doReload() {
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
                profileList = try ProfileManager.list()
            } catch {
                alert = Alert(error)
                return
            }
            if profileList.isEmpty {
                return
            }

            selectedProfileID = SharedPreferences.selectedProfileID
            if profileList.filter({ profile in
                profile.id == selectedProfileID
            })
            .isEmpty {
                selectedProfileID = profileList[0].id!
                SharedPreferences.selectedProfileID = selectedProfileID
            }
        }
    }

    private func doReloadSystemProxy() {
        do {
            let status = try LibboxNewStandaloneCommandClient()!.getSystemProxyStatus()
            systemProxyAvailable = status.available
            systemProxyEnabled = status.enabled
        } catch {
            alert = Alert(error)
        }
    }
}
