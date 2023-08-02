import Foundation
import Libbox
import Library
import Network
import SwiftUI

public struct ProfileView: View {
    public static let notificationName = Notification.Name("\(FilePath.packageName).update-profile")

    @Environment(\.importProfile) private var importProfile
    @Environment(\.importRemoteProfile) private var importRemoteProfile
    @State private var importRemoteProfileRequest: NewProfileView.ImportRequest?
    @State private var importRemoteProfilePresented = false

    @State private var isLoading = true
    @State private var isUpdating = false

    @State private var alert: Alert?
    @State private var profileList: [Profile] = []

    #if os(iOS) || os(tvOS)
        @State private var editMode = EditMode.inactive
    #elseif os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    #if os(tvOS)
        @Environment(\.devicePickerSupports) private var devicePickerSupports
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
                #if os(iOS) || os(tvOS)
                    ZStack {
                        if let importRemoteProfileRequest {
                            NavigationDestinationCompat(isPresented: $importRemoteProfilePresented) {
                                NewProfileView(importRemoteProfileRequest) {
                                    Task.detached {
                                        doReload()
                                    }
                                }
                            }
                        }
                        FormView {
                            #if os(iOS) || os(tvOS)
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
                            #endif
                            #if os(tvOS)
                                if ApplicationLibrary.inPreview || devicePickerSupports(.applicationService(name: "sing-box"), parameters: { .applicationService }) {
                                    NavigationLink {
                                        ImportProfileView {
                                            Task.detached {
                                                doReload()
                                            }
                                        }
                                    } label: {
                                        Text("Import Profile").foregroundColor(.accentColor)
                                    }
                                }
                            #endif
                            if profileList.isEmpty {
                                Text("Empty Profiles")
                            } else {
                                List {
                                    ForEach(profileList, id: \.mustID) { profile in
                                        viewBuilder {
                                            if editMode.isEditing == true {
                                                Text(profile.name)
                                            } else {
                                                ProfileItem(self, profile)
                                            }
                                        }
                                    }
                                    .onMove(perform: moveProfile)
                                    .onDelete(perform: deleteProfile)
                                }
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
                                    ProfileItem(self, profile)
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
        .alertBinding($alert, $isLoading)
        .onAppear {
            if let profile = importProfile.wrappedValue {
                importProfile.wrappedValue = nil
                createImportProfileDialog(profile)
            }
            if let remoteProfile = importRemoteProfile.wrappedValue {
                importRemoteProfile.wrappedValue = nil
                createImportRemoteProfileDialog(remoteProfile)
            }
            #if os(macOS)
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(forName: ProfileView.notificationName, object: nil, queue: .main) { _ in
                        Task.detached {
                            doReload()
                        }
                    }
                }
            #endif
        }
        .onChangeCompat(of: importProfile.wrappedValue) { newValue in
            if let newValue {
                importProfile.wrappedValue = nil
                createImportProfileDialog(newValue)
            }
        }
        .onChangeCompat(of: importRemoteProfile.wrappedValue) { newValue in
            if let newValue {
                importRemoteProfile.wrappedValue = nil
                createImportRemoteProfileDialog(newValue)
            }
        }
        #if os(macOS)
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

    private func createImportProfileDialog(_ profile: LibboxProfileContent) {
        alert = Alert(
            title: Text("Import Profile"),
            message: Text("Are you sure to import profile \(profile.name)?"),
            primaryButton: .default(Text("Import")) {
                do {
                    try profile.importProfile()
                } catch {
                    alert = Alert(error)
                    return
                }
                Task.detached {
                    doReload()
                }
            },
            secondaryButton: .cancel()
        )
    }

    private func createImportRemoteProfileDialog(_ newValue: LibboxImportRemoteProfile) {
        importRemoteProfileRequest = .init(name: newValue.name, url: newValue.url)
        alert = Alert(
            title: Text("Import Remote Profile"),
            message: Text("Are you sure to import remote profile \(newValue.name)? You will connect to \(newValue.host) to download the configuration."),
            primaryButton: .default(Text("Import")) {
                #if os(iOS) || os(tvOS)
                    importRemoteProfilePresented = true
                #elseif os(macOS)
                    openWindow(id: NewProfileView.windowID, value: importRemoteProfileRequest!)
                #endif
            },
            secondaryButton: .cancel()
        )
    }

    private func deleteSelectedProfiles(_ profileID: [Int64]) {
        do {
            if try ProfileManager.delete(by: profileID) > 0 {
                isLoading = true
            }
        } catch {
            alert = Alert(error)
        }
    }

    private func doReload() {
        defer {
            isLoading = false
        }
        if ApplicationLibrary.inPreview {
            profileList = [
                Profile(id: 0, name: "profile local", type: .local, path: ""),
                Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0)),
            ]
        } else {
            do {
                profileList = try ProfileManager.list()
            } catch {
                alert = Alert(error)
                return
            }
        }
    }

    private func updateProfile(_ profile: Profile) {
        do {
            _ = try profile.updateRemoteProfile()
        } catch {
            alert = Alert(error)
        }
        isUpdating = false
    }

    private func deleteProfile(_ profile: Profile) {
        Task.detached {
            do {
                _ = try ProfileManager.delete(profile)
            } catch {
                alert = Alert(error)
                return
            }
            doReload()
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
            alert = Alert(error)
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
                alert = Alert(error)
            }
        }
    }

    public struct ProfileItem: View {
        private let parent: ProfileView
        private let profile: Profile
        public init(_ parent: ProfileView, _ profile: Profile) {
            self.parent = parent
            self.profile = profile
        }

        public var body: some View {
            #if os(iOS) || os(macOS)
                if #available(iOS 16.0, macOS 13.0,*) {
                    body0.draggable(profile)
                } else {
                    body0
                }
            #else
                body0
            #endif
        }

        private var body0: some View {
            viewBuilder {
                #if !os(macOS)
                    NavigationLink {
                        EditProfileView {
                            Task.detached {
                                parent.doReload()
                            }
                        }.environmentObject(profile)
                    } label: {
                        Text(profile.name)
                    }
                    .contextMenu {
                        ShareButton(parent.$alert) {
                            Label("Share", systemImage: "square.and.arrow.up.fill")
                        } items: {
                            try [profile.toContent().generateShareFile()]
                        }
                        if profile.type == .remote {
                            Button {
                                parent.isUpdating = true
                                Task.detached {
                                    parent.updateProfile(profile)
                                }
                            } label: {
                                Label("Update", systemImage: "arrow.clockwise")
                            }
                        }
                        Button(role: .destructive) {
                            parent.deleteProfile(profile)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
                #else
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
                                    parent.isUpdating = true
                                    Task.detached {
                                        parent.updateProfile(profile)
                                    }
                                }, label: {
                                    Image(systemName: "arrow.clockwise")
                                })
                            }
                            ShareButton(parent.$alert) {
                                Image(systemName: "square.and.arrow.up.fill")
                            } items: {
                                try [profile.toContent().generateShareFile()]
                            }
                            Button(action: {
                                parent.openWindow(id: EditProfileWindowView.windowID, value: profile.mustID)
                            }, label: {
                                Image(systemName: "pencil")
                            })
                            Button(action: {
                                parent.deleteProfile(profile)
                            }, label: {
                                Image(systemName: "trash.fill")
                            })
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
        }
    }
}
