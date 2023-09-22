import ApplicationLibrary
import Foundation
import Libbox
import Library
import MacControlCenterUI
import MenuBarExtraAccess
import SwiftUI

@MainActor
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
                        Task {
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
        @State private var alert: Alert?

        init(_ profile: ExtensionProfile) {
            self.profile = profile
        }

        var body: some View {
            Toggle(isOn: Binding(get: {
                profile.status.isConnected
            }, set: { _ in
                Task {
                    await switchProfile(!profile.status.isConnected)
                }
            })) {}
                .toggleStyle(.switch)
                .disabled(!profile.status.isEnabled)
                .alertBinding($alert)
        }

        private func switchProfile(_ isEnabled: Bool) async {
            do {
                if isEnabled {
                    try await profile.start()
                } else {
                    profile.stop()
                }
            } catch {
                alert = Alert(error)
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
        @State private var observer: Any?
        @State private var alert: Alert?

        var body: some View {
            viewBuilder {
                if isLoading {
                    ProgressView().onAppear {
                        Task {
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
                        .onChangeCompat(of: selectedProfileID) {
                            reasserting = true
                            Task {
                                await switchProfile(selectedProfileID!)
                            }
                        }
                        .disabled(!profile.status.isSwitchable || reasserting)
                    }
                }
            }
            .onAppear {
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(forName: OverviewView.NotificationUpdateSelectedProfile, object: nil, queue: nil, using: { notification in
                        selectedProfileID = notification.object as! Int64
                    })
                }
            }
            .onDisappear {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
            .alertBinding($alert)
        }

        private func doReload() async {
            defer {
                isLoading = false
            }
            do {
                profileList = try await ProfileManager.list()
            } catch {
                alert = Alert(error)
                return
            }
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
        }

        private func switchProfile(_ newProfileID: Int64) async {
            await SharedPreferences.selectedProfileID.set(newProfileID)
            NotificationCenter.default.post(name: OverviewView.NotificationUpdateSelectedProfile, object: newProfileID)
            if profile.status.isConnected {
                do {
                    try await serviceReload()
                } catch {
                    alert = Alert(error)
                }
            }
            reasserting = false
        }

        private nonisolated func serviceReload() async throws {
            try LibboxNewStandaloneCommandClient()?.serviceReload()
        }
    }
}
