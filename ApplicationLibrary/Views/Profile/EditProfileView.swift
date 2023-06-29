import Library
import SwiftUI

public struct EditProfileView: View {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @EnvironmentObject private var profile: Profile

    @State private var isLoading = false
    @State private var isChanged = false
    @State private var errorPresented = false
    @State private var errorMessage = ""

    public init() {}

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
            }
            if profile.type == .remote {
                Section("Status") {
                    FormTextItem("Last Updated", profile.lastUpdatedString)
                }
            }
            #if os(iOS)
                Section("Action") {
                    if profile.type != .remote {
                        NavigationLink {
                            EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                        } label: {
                            Text("Edit Content").foregroundColor(.accentColor)
                        }
                    } else {
                        NavigationLink {
                            EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                        } label: {
                            Text("View Content").foregroundColor(.accentColor)
                        }
                        Button("Update") {
                            isLoading = true
                            Task.detached {
                                await updateProfile()
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            #endif
        }
        .onChange(of: profile.name, perform: { _ in
            isChanged = true
        })
        .onChange(of: profile.remoteURL, perform: { _ in
            isChanged = true
        })
        .onChange(of: profile.autoUpdate, perform: { _ in
            isChanged = true
        })
        .disabled(isLoading)
        #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: {
                        isLoading = true
                        Task.detached {
                            await saveProfile()
                        }
                    }, label: {
                        Image("save", bundle: ApplicationLibrary.bundle, label: Text("Save"))
                    })
                    .disabled(isLoading || !isChanged)
                    if profile.type != .remote {
                        Button(action: {
                            openWindow(id: EditProfileContentView.windowID, value: EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                        }, label: {
                            Label("Edit Content", systemImage: "pencil")
                        })
                        .disabled(isLoading)
                    } else {
                        Button(action: {
                            isLoading = true
                            Task.detached {
                                await updateProfile()
                            }
                        }, label: {
                            Label("Update", systemImage: "arrow.clockwise")
                        })
                        .disabled(isLoading)
                        Button(action: {
                            openWindow(id: EditProfileContentView.windowID, value: EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                        }, label: {
                            Label("View Content", systemImage: "doc.text.fill")
                        })
                        .disabled(isLoading)
                    }
                }
            }
        #elseif os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        isLoading = true
                        Task.detached {
                            await saveProfile()
                        }
                    }.disabled(!isChanged)
                }
            }
        #endif
            .alert(isPresented: $errorPresented) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok"))
                )
            }
            .navigationTitle("Edit Profile")
    }

    private func updateProfile() async {
        defer {
            isLoading = false
        }
        do {
            try await Task.sleep(nanoseconds: UInt64(100 * Double(NSEC_PER_MSEC)))
            try profile.updateRemoteProfile()
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
        }
    }

    private func saveProfile() async {
        do {
            _ = try ProfileManager.update(profile)
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
            return
        }
        isChanged = false
        isLoading = false
        await MainActor.run {
            NotificationCenter.default.post(name: ProfileView.notificationName, object: nil)
        }
    }
}
