import Library
import SwiftUI

@MainActor
public struct EditProfileView: View {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profile: Profile

    @State private var isLoading = false
    @State private var isChanged = false
    @State private var alert: Alert?
    private let updateCallback: (() -> Void)?
    public init(_ updateCallback: (() -> Void)? = nil) {
        self.updateCallback = updateCallback
    }

    public var body: some View {
        FormView {
            FormItem("Name") {
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
                FormItem("Path") {
                    TextField("Path", text: $profile.path, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
            } else if profile.type == .remote {
                FormItem("URL") {
                    TextField("URL", text: $profile.remoteURL.unwrapped(""), prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Auto Update", isOn: $profile.autoUpdate)
                FormItem("Auto Update Interval") {
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
            #if os(iOS) || os(tvOS)
                Section("Action") {
                    if profile.type != .remote {
                        #if os(iOS)
                            NavigationLink {
                                EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                            } label: {
                                Text("Edit Content").foregroundColor(.accentColor)
                            }
                        #endif
                    } else {
                        #if os(iOS)
                            NavigationLink {
                                EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                            } label: {
                                Text("View Content").foregroundColor(.accentColor)
                            }
                            ProfileShareButton($alert, profile) {
                                Text("Share")
                            }
                        #endif
                        ShareButtonCompat($alert) {
                            Text("Share URL")
                        } itemURL: {
                            profile.shareLink
                        }
                        Button("Update") {
                            isLoading = true
                            Task {
                                await updateProfile()
                            }
                        }
                        .disabled(isLoading)
                    }
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteProfile()
                        }
                    }
                }
            #endif
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
                    if profile.type != .remote {
                        Button {
                            openWindow(id: EditProfileContentView.windowID, value: EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                        } label: {
                            Label("Edit Content", systemImage: "pencil")
                        }
                        .disabled(isLoading)
                    } else {
                        Button {
                            isLoading = true
                            Task {
                                await updateProfile()
                            }
                        } label: {
                            Label("Update", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                        Button {
                            openWindow(id: EditProfileContentView.windowID, value: EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                        } label: {
                            Label("View Content", systemImage: "doc.text.fill")
                        }
                        .disabled(isLoading)
                    }
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
            #if os(iOS) || os(tvOS)
                try await UIProfileUpdateTask.configure()
            #else
                try await ProfileUpdateTask.configure()
            #endif
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
        await performCallback()
        dismiss()
    }

    private func saveProfile() async {
        do {
            _ = try await ProfileManager.update(profile)
        } catch {
            alert = Alert(error)
            return
        }
        isChanged = false
        isLoading = false
        await performCallback()
    }

    private func performCallback() async {
        if let updateCallback {
            updateCallback()
        } else {
            NotificationCenter.default.post(name: ProfileView.notificationName, object: nil)
        }
    }
}
