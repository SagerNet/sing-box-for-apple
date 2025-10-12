#if os(tvOS)

    import DeviceDiscoveryUI
    import Libbox
    import Library
    import SwiftUI

    @MainActor
    public struct ImportProfileView: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = ImportProfileViewModel()

        public init() {}
        public var body: some View {
            VStack(alignment: .center) {
                if !viewModel.selected {
                    Form {
                        Section {
                            EmptyView()
                        } footer: {
                            Text("To import configurations from your iPhone or iPad, make sure sing-box is the **same version** on both devices and **VPN is disabled**.")
                        }

                        DevicePicker(
                            .applicationService(name: "sing-box:profile"))
                        { endpoint in
                            viewModel.selected = true
                            Task {
                                await viewModel.handleEndpoint(endpoint, environments: environments, dismiss: dismiss)
                            }
                        } label: {
                            Text("Select Device")
                        } fallback: {
                            EmptyView()
                        } parameters: {
                            .applicationService
                        }
                    }
                } else if let profiles = viewModel.profiles {
                    Form {
                        Section {
                            EmptyView()
                        } footer: {
                            Text("\(profiles.count) Profiles")
                        }
                        ForEach(profiles, id: \.profileID) { profile in
                            Button(profile.name) {
                                viewModel.isLoading = true
                                Task {
                                    viewModel.selectProfile(profileID: profile.profileID)
                                    viewModel.isLoading = false
                                }
                            }.disabled(viewModel.isLoading || viewModel.isImporting)
                        }
                    }
                } else {
                    Text("Connecting...")
                }
            }
            .focusSection()
            .alertBinding($viewModel.alert)
            .navigationTitle("Import Profile")
        }
    }

#endif
