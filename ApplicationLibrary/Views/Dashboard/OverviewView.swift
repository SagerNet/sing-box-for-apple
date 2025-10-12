import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct OverviewView: View {
    @Environment(\.selection) private var selection
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @Binding private var profileList: [ProfilePreview]
    @Binding private var selectedProfileID: Int64
    @Binding private var systemProxyAvailable: Bool
    @Binding private var systemProxyEnabled: Bool
    @StateObject private var viewModel = OverviewViewModel()

    private var selectedProfileIDLocal: Binding<Int64> {
        $selectedProfileID.withSetter { newValue in
            viewModel.reasserting = true
            Task { [self] in
                await viewModel.switchProfile(newValue, profile: profile, environments: environments)
            }
        }
    }

    public init(_ profileList: Binding<[ProfilePreview]>, _ selectedProfileID: Binding<Int64>, _ systemProxyAvailable: Binding<Bool>, _ systemProxyEnabled: Binding<Bool>) {
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
                                    Task {
                                        await viewModel.setSystemProxyEnabled(newValue, profile: profile)
                                    }
                                }
                        }
                        Section("Profile") {
                            Picker(selection: selectedProfileIDLocal) {
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
                                    Task {
                                        await viewModel.setSystemProxyEnabled(newValue, profile: profile)
                                    }
                                }
                        }
                        Section("Profile") {
                            ForEach(profileList, id: \.id) { profile in
                                Picker(profile.name, selection: selectedProfileIDLocal) {
                                    Text("").tag(profile.id)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }
                    #endif
                }
            }
        }
        .alertBinding($viewModel.alert)
        .disabled(!ApplicationLibrary.inPreview && (!profile.status.isSwitchable || viewModel.reasserting))
    }
}
