import ApplicationLibrary
import Foundation
import Libbox
import Library
import MacControlCenterUI
import MenuBarExtraAccess
import SwiftUI

public struct MenuView: View {
    @Environment(\.openWindow) private var openWindow

    private static let sliderWidth: CGFloat = 270

    @Binding private var isMenuPresented: Bool

    @State private var isLoading = true
    @State private var profile: ExtensionProfile?

    public init(isMenuPresented: Binding<Bool>) {
        _isMenuPresented = isMenuPresented
    }

    public var body: some View {
        MacControlCenterMenu(isPresented: $isMenuPresented) {
            MenuHeader("sing-box") {
                if isLoading {
                    Text("Loading...").foregroundColor(.secondary).onAppear {
                        Task.detached {
                            await loadProfile()
                        }
                    }
                } else if let profile {
                    Text(LibboxVersion()).foregroundColor(.secondary)
                    StatusSwitch(profile)
                } else {
                    Text("NetworkExtension not installed")
                }
            }
            .frame(minWidth: MenuView.sliderWidth)
            if let profile {
                ProfilePicker(profile)
            }
            Divider()
            MenuCommand {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
                    dockApp.activate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            } label: {
                Text("Open")
            }
            MenuCommand {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
            }
        }
    }

    private func loadProfile() async {
        profile = try? await ExtensionProfile.load()
        if let profile {
            profile.register()
        }
        isLoading = false
    }

    private struct StatusSwitch: View {
        @ObservedObject private var profile: ExtensionProfile
        @State private var errorPresented = false
        @State private var errorMessage = ""

        init(_ profile: ExtensionProfile) {
            self.profile = profile
        }

        var body: some View {
            Toggle(isOn: Binding(get: {
                profile.status.isConnected
            }, set: { _ in
                Task.detached {
                    await switchProfile(!profile.status.isConnected)
                }
            })) {}
                .toggleStyle(.switch)
                .disabled(!profile.status.isEnabled)
                .alert(isPresented: $errorPresented) {
                    Alert(
                        title: Text("Error"),
                        message: Text(errorMessage),
                        dismissButton: .default(Text("Ok"))
                    )
                }
        }

        private func switchProfile(_ isEnabled: Bool) async {
            do {
                if isEnabled {
                    try await profile.start()
                } else {
                    profile.stop()
                }
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
                return
            }
        }
    }

    private struct ProfilePicker: View {
        @ObservedObject private var profile: ExtensionProfile

        init(_ profile: ExtensionProfile) {
            self.profile = profile
        }

        @State private var isLoading = true
        @State private var profileList: [Profile] = []
        @State private var selectedProfileID: Int64!
        @State private var reasserting = false

        @State private var errorPresented = false
        @State private var errorMessage = ""
        @State private var observer: Any?

        var body: some View {
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
                        MenuSection("Profile")
                        Picker("", selection: $selectedProfileID) {
                            ForEach(profileList, id: \.id) { profile in
                                Text(profile.name)
                            }
                        }
                        .pickerStyle(.inline)
                        .onChange(of: selectedProfileID) { _ in
                            reasserting = true
                            Task.detached {
                                await switchProfile(selectedProfileID!)
                            }
                        }
                        .disabled(!profile.status.isSwitchable || reasserting)
                    }
                }
            }
            .onAppear {
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(forName: ActiveDashboardView.NotificationUpdateSelectedProfile, object: nil, queue: nil, using: { _ in
                        doReload()
                    })
                }
            }
            .onDisappear {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
            .alert(isPresented: $errorPresented) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok"))
                )
            }
        }

        private func doReload() {
            defer {
                isLoading = false
            }
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
}
