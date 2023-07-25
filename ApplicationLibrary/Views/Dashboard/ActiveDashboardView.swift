import Foundation
import Libbox
import Library
import SwiftUI

public struct ActiveDashboardView: View {
    public static let NotificationUpdateSelectedProfile = Notification.Name("update-selected-profile")

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.selection) private var selection

    @EnvironmentObject private var profile: ExtensionProfile

    @State private var isLoading = true
    @State private var profileList: [Profile] = []
    @State private var selectedProfileID: Int64!
    @State private var reasserting = false
    @State private var observer: Any?

    @State private var errorPresented = false
    @State private var errorMessage = ""

    public init() {}

    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        await doReload()
                    }
                }
            } else {
                if profileList.isEmpty {
                    Text("Empty profiles")
                } else {
                    VStack {
                        #if os(iOS)
                            if ApplicationLibrary.inPreview || profile.status.isConnected {
                                ExtensionStatusView()
                                    .listStyle(.automatic)
                                    .navigationBarTitleDisplayMode(.inline)
                            }
                            FormView {
                                StartStopButton()
                                Section("Profile") {
                                    Picker(selection: $selectedProfileID) {
                                        ForEach(profileList, id: \.id) { profile in
                                            Text(profile.name).tag(profile.id)
                                        }
                                    } label: {}
                                        .pickerStyle(.inline)
                                }
                            }
                        #else
                            if ApplicationLibrary.inPreview || profile.status.isConnected {
                                ExtensionStatusView()
                            }
                            FormView {
                                Section("Profile") {
                                    ForEach(profileList, id: \.id) { profile in
                                        Picker(profile.name, selection: $selectedProfileID) {
                                            Text("").tag(profile.id)
                                        }
                                    }
                                    .pickerStyle(.radioGroup)
                                }
                            }
                        #endif
                    }
                    .onChange(of: selectedProfileID) { _ in
                        reasserting = true
                        Task.detached {
                            await switchProfile(selectedProfileID!)
                        }
                    }
                    .disabled(!ApplicationLibrary.inPreview && (!profile.status.isSwitchable || reasserting))
                }
            }
        }
        .alert(isPresented: $errorPresented) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Ok"))
            )
        }
        #if os(iOS)
        .onChange(of: scenePhase, perform: { newValue in
            if newValue == .active {
                Task.detached {
                    await doReload()
                }
            }
        })
        .onChange(of: selection.wrappedValue, perform: { newValue in
            if newValue == .dashboard {
                Task.detached {
                    await doReload()
                }
            }
        })
        #elseif os(macOS)
        .onAppear {
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: ActiveDashboardView.NotificationUpdateSelectedProfile, object: nil, queue: nil, using: { _ in
                    Task.detached {
                        await doReload()
                    }
                })
            }
        }
        .onDisappear {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        #endif
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
            selectedProfileID = 0
        } else {
            do {
                profileList = try ProfileManager.list()
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
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

    private func switchProfile(_ newProfileID: Int64) {
        SharedPreferences.selectedProfileID = newProfileID
        NotificationCenter.default.post(name: ActiveDashboardView.NotificationUpdateSelectedProfile, object: nil)
        if profile.status.isConnected {
            do {
                try LibboxNewStandaloneCommandClient(FilePath.sharedDirectory.relativePath)?.serviceReload()
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
            }
        }
        reasserting = false
    }
}
