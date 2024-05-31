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
    public static let MenuDisclosureSectionPaddingFix: CGFloat = -14.0

    @Binding private var isMenuPresented: Bool

    @State private var isLoading = true
    @State private var profile: ExtensionProfile?
    
    @EnvironmentObject private var commandClient: CommandClient

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
            if( commandClient.clashModeList.count > 0) {
                ClashOutboundPicker()
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
                    try await profile.stop()
                }
            } catch {
                alert = Alert(error)
                return
            }
        }
    }

    private struct ProfilePicker: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @ObservedObject private var profile: ExtensionProfile

        init(_ profile: ExtensionProfile) {
            self.profile = profile
        }

        @State private var isLoading = true
        @State private var profileList: [ProfilePreview] = []
        @State private var selectedProfileID: Int64 = 0
        @State private var reasserting = false
        @State private var alert: Alert?
        @State private var isExpanded = false

        private var selectedProfileIDLocal: Binding<Int64> {
            $selectedProfileID.withSetter { newValue in
                reasserting = true
                Task { [self] in
                    await switchProfile(newValue)
                }
            }
        }

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
                        Divider()
                        MenuDisclosureSection(
                            profileList.firstIndex(where: { $0.id == selectedProfileIDLocal.wrappedValue }).map { "Profile: \(profileList[$0].name)" } ?? "Profile",
                            divider: false,
                            isExpanded: $isExpanded
                        ) {
                            Picker("", selection: selectedProfileIDLocal) {
                                ForEach(profileList, id: \.id) { profile in
                                    Text(profile.name).frame(maxWidth: .infinity, alignment: .leading) 
                                }
                            }
                            .pickerStyle(.inline)
                            .disabled(!profile.status.isSwitchable || reasserting)
                        }
                        .padding(.leading, MenuView.MenuDisclosureSectionPaddingFix)
                        .padding(.trailing, MenuView.MenuDisclosureSectionPaddingFix)
                    }
                }
            }
            .onReceive(environments.profileUpdate) { _ in
                Task {
                    await doReload()
                }
            }
            .onReceive(environments.selectedProfileUpdate) { _ in
                Task {
                    selectedProfileID = await SharedPreferences.selectedProfileID.get()
                }
            }
            .alertBinding($alert)
        }

        private func doReload() async {
            defer {
                isLoading = false
            }
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
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
                selectedProfileID = profileList[0].id
                await SharedPreferences.selectedProfileID.set(selectedProfileID)
            }
        }

        private func switchProfile(_ newProfileID: Int64) async {
            await SharedPreferences.selectedProfileID.set(newProfileID)
            environments.selectedProfileUpdate.send()
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
            try LibboxNewStandaloneCommandClient()!.serviceReload()
        }
    }
    
    private struct ClashOutboundPicker: View {
        @EnvironmentObject private var commandClient: CommandClient
        @State private var isclashModeExpanded = false
        @State private var alert: Alert?
        
        private var clashLists: [MenuEntry] {
            commandClient.clashModeList.map { stringValue in
                MenuEntry(name: stringValue, systemImage: "")
            }
        }
        
        var body: some View {
            viewBuilder {
                Divider()
                MenuDisclosureSection("Outbound: " + commandClient.clashMode, divider: false, isExpanded: $isclashModeExpanded) {
                    MenuScrollView(maxHeight: 135) {
                        ForEach(commandClient.clashModeList, id: \.self) { it in
                            MenuCommand {
                                commandClient.clashMode = it;
                            } label: {
                                if it == commandClient.clashMode {
                                    Image(systemName: "play.fill")
                                }
                                Text(it)
                            }
                            .padding(.leading, MenuView.MenuDisclosureSectionPaddingFix)
                            .padding(.trailing, MenuView.MenuDisclosureSectionPaddingFix)
                        }
                    }
                }
                .padding(.leading, MenuView.MenuDisclosureSectionPaddingFix)
                .padding(.trailing, MenuView.MenuDisclosureSectionPaddingFix)
            }
            .alertBinding($alert)
        }
        private nonisolated func setClashMode(_ newMode: String) async {
            do {
                try LibboxNewStandaloneCommandClient()!.setClashMode(newMode)
            } catch {
                await MainActor.run {
                    alert = Alert(error)
                }
            }
        }
    }
}
