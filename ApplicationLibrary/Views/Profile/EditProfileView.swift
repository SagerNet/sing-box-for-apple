import Libbox
import Library
import SwiftUI

@MainActor
public struct EditProfileView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profile: Profile

    @State private var isLoading = false
    @State private var isChanged = false
    @State private var alert: Alert?
    @State private var shareLinkPresented = false
    @State private var shareLinkText: String?

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
                }
            } else if profile.type == .remote {
                FormItem(String(localized: "URL")) {
                    TextField("URL", text: $profile.remoteURL.unwrapped(""), prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Auto Update", isOn: $profile.autoUpdate)
                FormItem(String(localized: "Auto Update Interval")) {
                    TextField("Auto Update Interval", text: $profile.autoUpdateInterval.stringBinding(defaultValue: 60), prompt: Text("In Minutes"))
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                }
            }
            if profile.type == .remote {
                Section("Status") {
                    FormTextItem("Last Updated", profile.lastUpdatedString)
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
                        isLoading = true
                        Task {
                            await updateProfile()
                        }
                    } label: {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                    .foregroundColor(.accentColor)
                    .disabled(isLoading)
                }
                FormButton(role: .destructive) {
                    Task {
                        await deleteProfile()
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .foregroundColor(.red)
            }
        }
        .onChangeCompat(of: profile.name) {
            isChanged = true
        }
        .onChangeCompat(of: profile.remoteURL) {
            isChanged = true
        }
        .onChangeCompat(of: profile.autoUpdate) {
            isChanged = true
        }
        .disabled(isLoading)
        #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        isLoading = true
                        Task {
                            await saveProfile()
                        }
                    } label: {
                        Image("save", bundle: ApplicationLibrary.bundle, label: Text("Save"))
                    }
                    .disabled(isLoading || !isChanged)
                }
            }
        #elseif os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        isLoading = true
                        Task {
                            await saveProfile()
                        }
                    }.disabled(!isChanged)
                }
            }
        #endif
            .alertBinding($alert)
            .navigationTitle("Edit Profile")
    }

    private func updateProfile() async {
        defer {
            isLoading = false
        }
        do {
            try await Task.sleep(nanoseconds: UInt64(100 * Double(NSEC_PER_MSEC)))
            try await profile.updateRemoteProfile()
            environments.profileUpdate.send()
        } catch {
            alert = Alert(error)
        }
    }

    private func deleteProfile() async {
        do {
            try await ProfileManager.delete(profile)
        } catch {
            alert = Alert(error)
            return
        }
        environments.profileUpdate.send()
        dismiss()
    }

    private func saveProfile() async {
        do {
            _ = try await ProfileManager.update(profile)
            #if os(iOS) || os(tvOS)
                try await UIProfileUpdateTask.configure()
            #else
                try await ProfileUpdateTask.configure()
            #endif
        } catch {
            alert = Alert(error)
            return
        }
        isChanged = false
        isLoading = false
        environments.profileUpdate.send()
    }
}
