import Foundation
import Libbox
import Library
import SwiftUI

public struct OverviewView: View {
    public static let NotificationUpdateSelectedProfile = Notification.Name("update-selected-profile")

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.selection) private var selection
    @EnvironmentObject private var profile: ExtensionProfile
    @Binding private var profileList: [Profile]
    @Binding private var selectedProfileID: Int64!
    @State private var alert: Alert?
    @State private var reasserting = false
    @State private var observer: Any?

    public init(_ profileList: Binding<[Profile]>, _ selectedProfileID: Binding<Int64?>) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
    }

    public var body: some View {
        VStack {
            if ApplicationLibrary.inPreview || profile.status.isConnected {
                ExtensionStatusView()
            }
            FormView {
                #if os(iOS) || os(tvOS)
                    StartStopButton()
                    Section("Profile") {
                        Picker(selection: $selectedProfileID) {
                            ForEach(profileList, id: \.id) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        } label: {}
                            .pickerStyle(.inline)
                    }
                #elseif os(macOS)
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
}
