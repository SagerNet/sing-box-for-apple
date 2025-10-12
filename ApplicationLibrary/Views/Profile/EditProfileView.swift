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
                    FormTextItem("Last Updated", profile.lastUpdated!.myFormat)
                }
            }
            Section("Action") {
                if profile.type != .remote {
                    #if os(iOS) || os(macOS)
                        FormNavigationLink {
                            EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                        } label: {
                            Label("Edit Content", systemImage: "pencil")
                                .foregroundColor(.accentColor)
                        }
                    #endif
                } else {
                    #if os(iOS) || os(macOS)
                        FormNavigationLink {
                            EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                        } label: {
                            Label("View Content", systemImage: "doc.fill")
                                .foregroundColor(.accentColor)
                        }
                    #endif
                    FormButton {
                        viewModel.isLoading = true
                        Task {
                            await viewModel.updateProfile(profile, environments: environments)
                        }
                    } label: {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                    .foregroundColor(.accentColor)
                    .disabled(viewModel.isLoading)
                }
                FormButton(role: .destructive) {
                    Task {
                        await viewModel.deleteProfile(profile, environments: environments, dismiss: dismiss)
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .foregroundColor(.red)
            }
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
        #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        viewModel.isLoading = true
                        Task {
                            await viewModel.saveProfile(profile, environments: environments)
                        }
                    } label: {
                        Image("save", bundle: ApplicationLibrary.bundle, label: Text("Save"))
                    }
                    .disabled(viewModel.isLoading || !viewModel.isChanged)
                }
            }
        #elseif os(iOS)
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
            .alertBinding($viewModel.alert)
            .navigationTitle("Edit Profile")
    }
}
