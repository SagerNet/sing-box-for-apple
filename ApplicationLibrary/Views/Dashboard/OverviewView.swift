import Foundation
import Libbox
import Library
import SwiftUI

public struct OverviewView: View {
    public static let NotificationUpdateSelectedProfile = Notification.Name("update-selected-profile")

    @Environment(\.selection) private var selection
    @EnvironmentObject private var profile: ExtensionProfile
    @Binding private var profileList: [Profile]
    @Binding private var selectedProfileID: Int64!
    @Binding private var systemProxyAvailable: Bool
    @Binding private var systemProxyEnabled: Bool
    @State private var alert: Alert?
    @State private var reasserting = false
    @State private var observer: Any?

    public init(_ profileList: Binding<[Profile]>, _ selectedProfileID: Binding<Int64?>, _ systemProxyAvailable: Binding<Bool>, _ systemProxyEnabled: Binding<Bool>) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
        _systemProxyAvailable = systemProxyAvailable
        _systemProxyEnabled = systemProxyEnabled
    }

    public var body: some View {
        VStack {
            if ApplicationLibrary.inPreview || profile.status.isConnected {
                ExtensionStatusView()
                ClashModeView()
            }
            if profileList.isEmpty {
                Text("Empty profiles")
            } else {
                FormView {
                    #if os(iOS) || os(tvOS)
                        StartStopButton()
                        if ApplicationLibrary.inPreview || profile.status.isConnectedStrict, systemProxyAvailable {
                            Toggle("HTTP Proxy", isOn: $systemProxyEnabled)
                                .onChangeCompat(of: systemProxyEnabled) { newValue in
                                    Task.detached {
                                        await setSystemProxyEnabled(newValue)
                                    }
                                }
                        }
                        Section("Profile") {
                            Picker(selection: $selectedProfileID) {
                                ForEach(profileList, id: \.id) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            } label: {}
                                .pickerStyle(.inline)
                        }
                    #elseif os(macOS)
                        if ApplicationLibrary.inPreview || profile.status.isConnectedStrict, systemProxyAvailable {
                            Toggle("HTTP Proxy", isOn: $systemProxyEnabled)
                                .onChangeCompat(of: systemProxyEnabled) { newValue in
                                    Task.detached {
                                        await setSystemProxyEnabled(newValue)
                                    }
                                }
                        }
                        Section("Profile") {
                            ForEach(profileList, id: \.id) { profile in
                                Picker(profile.name, selection: $selectedProfileID) {
                                    Text("").tag(profile.id)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }
                    #endif
                }
            }
        }
        .alertBinding($alert)
        .onChangeCompat(of: selectedProfileID) {
            reasserting = true
            Task.detached {
                await switchProfile(selectedProfileID!)
            }
        }
        .disabled(!ApplicationLibrary.inPreview && (!profile.status.isSwitchable || reasserting))
        #if os(macOS)
            .onAppear {
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(forName: OverviewView.NotificationUpdateSelectedProfile, object: nil, queue: nil, using: { newProfileID in
                        selectedProfileID = newProfileID.object as! Int64
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

    private func switchProfile(_ newProfileID: Int64) {
        SharedPreferences.selectedProfileID = newProfileID
        NotificationCenter.default.post(name: OverviewView.NotificationUpdateSelectedProfile, object: newProfileID)
        if profile.status.isConnected {
            do {
                try LibboxNewStandaloneCommandClient()!.serviceReload()
            } catch {
                alert = Alert(error)
            }
        }
        reasserting = false
    }

    private func setSystemProxyEnabled(_ isEnabled: Bool) {
        do {
            try LibboxNewStandaloneCommandClient()!.setSystemProxyEnabled(isEnabled)
            SharedPreferences.systemProxyEnabled = isEnabled
        } catch {
            alert = Alert(error)
        }
    }
}
