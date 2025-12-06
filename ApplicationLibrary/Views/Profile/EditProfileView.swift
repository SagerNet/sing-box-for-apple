import Libbox
import Library
import SwiftUI

@MainActor
public struct EditProfileView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profile: Profile
    @StateObject private var viewModel = EditProfileViewModel()

    public init() {}

    public var body: some View {
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    private var formContent: some View {
        FormView {
            FormItem(String(localized: "Name")) {
                TextField("Name", text: $profile.name, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
            }

            Picker(selection: $profile.type) {
                Text("Local").tag(ProfileType.local)
                Text("iCloud").tag(ProfileType.icloud)
                Text("Remote").tag(ProfileType.remote)
            } label: {
                Text("Type")
            }
            .disabled(true)
            if profile.type == .icloud {
                FormItem(String(localized: "Path")) {
                    TextField("Path", text: $profile.path, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                        .keyboardType(.asciiCapableNumberPad)
                    #endif
                }
            } else if profile.type == .remote {
                FormItem(String(localized: "URL")) {
                    TextField("URL", text: $profile.remoteURL.unwrapped(""), prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                        .keyboardType(.URL)
                    #endif
                }
                Toggle("Auto Update", isOn: $profile.autoUpdate)
                FormItem(String(localized: "Auto Update Interval")) {
                    TextField("Auto Update Interval", text: $profile.autoUpdateInterval.stringBinding(defaultValue: 60), prompt: Text("In Minutes"))
                        .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                        .keyboardType(.numberPad)
                    #endif
                }
            }
            if profile.type == .remote {
                Section("Status") {
                    FormTextItem("Last Updated", profile.lastUpdated!.relativeFormat)
                }
            }

            #if os(iOS) || os(tvOS)
                ProfileActionToolbar(profile: profile, viewModel: viewModel)
            #endif
        }
    }

    #if os(macOS)
        private var macOSBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Edit Profile")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                formContent
            }
            .safeAreaInset(edge: .bottom) {
                ProfileActionToolbar(profile: profile, viewModel: viewModel)
            }
            .onChangeCompat(of: profile.name) {
                viewModel.markAsChanged()
            }
            .onChangeCompat(of: profile.remoteURL) {
                viewModel.markAsChanged()
            }
            .onChangeCompat(of: profile.autoUpdate) {
                viewModel.markAsChanged()
            }
            .disabled(viewModel.isLoading)
            .alert($viewModel.alert)
        }
    #else
        private var iOSBody: some View {
            formContent
                .onChangeCompat(of: profile.name) {
                    viewModel.markAsChanged()
                }
                .onChangeCompat(of: profile.remoteURL) {
                    viewModel.markAsChanged()
                }
                .onChangeCompat(of: profile.autoUpdate) {
                    viewModel.markAsChanged()
                }
                .disabled(viewModel.isLoading)
            #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            viewModel.isLoading = true
                            Task {
                                await viewModel.saveProfile(profile, environments: environments)
                            }
                        }.disabled(!viewModel.isChanged)
                    }
                }
            #endif
                .alert($viewModel.alert)
                .navigationTitle("Edit Profile")
        }
    #endif
}
