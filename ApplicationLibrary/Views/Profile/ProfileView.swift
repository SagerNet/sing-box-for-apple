import Foundation
import Library
import SwiftUI

public struct ProfileView: View {
    public static let notificationName = Notification.Name("\(FilePath.packageName).update-profile")

    @State private var isLoading = true
    @State private var isUpdating = false

    @State private var errorPresented = false
    @State private var errorMessage = ""

    @State private var profileList: [Profile] = []

    #if os(iOS)
        @State private var editMode = EditMode.inactive
    #elseif os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @State private var observer: Any?

    public init() {}

    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        doReload()
                    }
                }
            } else {
                #if os(iOS)
                    FormView {
                        NavigationLink {
                            NewProfileView {
                                Task.detached {
                                    doReload()
                                }
                            }
                        } label: {
                            Text("New Profile").foregroundColor(.accentColor)
                        }
                        .disabled(editMode.isEditing)
                        if profileList.isEmpty {
                            Text("Empty Profiles")
                        } else {
                            List {
                                ForEach(profileList, id: \.mustID) { profile in
                                    viewBuilder {
                                        if editMode.isEditing == true {
                                            Text(profile.name)
                                        } else {
                                            NavigationLink {
                                                EditProfileView().environmentObject(profile)
                                            } label: {
                                                Text(profile.name)
                                            }
                                        }
                                    }
                                }
                                .onMove(perform: moveProfile)
                                .onDelete(perform: deleteProfile)
                            }
                        }
                    }
                #elseif os(macOS)
                    if profileList.isEmpty {
                        Text("Empty Profiles")
                    } else {
                        FormView {
                            List {
                                ForEach(profileList, id: \.mustID) { profile in

                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(profile.name)
                                            if profile.type == .remote {
                                                Spacer(minLength: 4)
                                                Text("Last Updated: \(profile.lastUpdatedString)").font(.caption)
                                            }
                                        }
                                        HStack {
                                            if profile.type == .remote {
                                                Button(action: {
                                                    isUpdating = true
                                                    Task.detached {
                                                        updateProfile(profile)
                                                    }
                                                }, label: {
                                                    Image(systemName: "arrow.clockwise")
                                                })
                                            }
                                            Button(action: {
                                                openWindow(id: EditProfileWindowView.windowID, value: profile.mustID)
                                            }, label: {
                                                Image(systemName: "pencil")
                                            })
                                            Button(action: {
                                                deleteProfile(profile)
                                            }, label: {
                                                Image(systemName: "trash.fill")
                                            })
                                        }
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .onMove(perform: moveProfile)
                                .onDelete(perform: deleteProfile)
                            }
                        }
                    }
                #endif
            }
        }
        .disabled(isUpdating)
        .navigationTitle("Profiles")
        #if os(macOS)
            .onAppear {
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(forName: ProfileView.notificationName, object: nil, queue: .main) { _ in
                        Task.detached {
                            doReload()
                        }
                    }
                }
            }
            .onDisappear {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                observer = nil
            }
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        openWindow(id: NewProfileView.windowID)
                    }, label: {
                        Label("New Profile", systemImage: "plus.square.fill")
                    })
                }
            }
        #elseif os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton().disabled(profileList.isEmpty)
                }
            }
            .environment(\.editMode, $editMode)
        #endif
    }

    private func deleteSelectedProfiles(_ profileID: [Int64]) {
        do {
            if try ProfileManager.delete(by: profileID) > 0 {
                isLoading = true
            }
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
        }
    }

    private func doReload() {
        defer {
            isLoading = false
        }
        do {
            profileList = try ProfileManager.list()
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
            return
        }
    }

    private func updateProfile(_ profile: Profile) {
        do {
            _ = try profile.updateRemoteProfile()
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
        }
        isUpdating = false
    }

    private func deleteProfile(_ profile: Profile) {
        Task.detached {
            do {
                _ = try ProfileManager.delete(profile)
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
                return
            }
            isLoading = true
        }
    }

    private func moveProfile(from source: IndexSet, to destination: Int) {
        profileList.move(fromOffsets: source, toOffset: destination)
        for (index, profile) in profileList.enumerated() {
            profile.order = UInt32(index)
        }
        do {
            try ProfileManager.update(profileList)
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
            return
        }
    }

    private func deleteProfile(where profileIndex: IndexSet) {
        let profileToDelete = profileIndex.map { index in
            profileList[index]
        }
        profileList.remove(atOffsets: profileIndex)
        Task.detached {
            do {
                _ = try ProfileManager.delete(profileToDelete)
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
            }
        }
    }
}
