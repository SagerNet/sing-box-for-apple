import Foundation
import Libbox
import Library
import Network
import SwiftUI

@MainActor
public struct ProfileView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.importProfile) private var importProfile
    @Environment(\.importRemoteProfile) private var importRemoteProfile
    @State private var importRemoteProfileRequest: NewProfileView.ImportRequest?
    @State private var importRemoteProfilePresented = false

    @State private var isLoading = true
    @State private var isUpdating = false

    @State private var alert: Alert?
    @State private var profileList: [ProfilePreview] = []

    #if os(iOS) || os(tvOS)
        @State private var editMode = EditMode.inactive
    #elseif os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    #if os(tvOS)
        @Environment(\.devicePickerSupports) private var devicePickerSupports
    #endif

    public init() {}
    public var body: some View {
        VStack {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await doReload()
                    }
                }
            } else {
                #if os(iOS) || os(tvOS)
                    ZStack {
                        if let importRemoteProfileRequest {
                            NavigationDestinationCompat(isPresented: $importRemoteProfilePresented) {
                                NewProfileView(importRemoteProfileRequest)
                            }
                        }
                        FormView {
                            #if os(iOS)
                                NavigationLink {
                                    NewProfileView()
                                } label: {
                                    Text("New Profile").foregroundColor(.accentColor)
                                }
                                .disabled(editMode.isEditing)
                            #elseif os(tvOS)
                                Section {
                                    NavigationLink {
                                        NewProfileView()
                                    } label: {
                                        Text("New Profile").foregroundColor(.accentColor)
                                    }
                                    if ApplicationLibrary.inPreview || devicePickerSupports(.applicationService(name: "sing-box"), parameters: { .applicationService }) {
                                        NavigationLink {
                                            ImportProfileView {
                                                await doReload()
                                            }
                                        } label: {
                                            Text("Import Profile").foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            #endif
                            if profileList.isEmpty {
                                Text("Empty profiles")
                            } else {
                                List {
                                    ForEach(profileList, id: \.id) { profile in
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
                        Text("Empty profiles")
                    } else {
                        FormView {
                            List {
                                ForEach(profileList, id: \.id) { profile in
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
        .onReceive(environments.profileUpdate) { _ in
            profileList = []
            isLoading = true
//            not updated, but why?
//            Task {
//                await doReload()
//            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: NewProfileView.windowID)
                } label: {
                    Label("New Profile", systemImage: "plus.square.fill")
                }
            }
        }
        #elseif os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton().disabled(profileList.isEmpty)
            }
        }
        #elseif os(tvOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if editMode == .inactive {
                    Button("Edit") {
                        editMode = .active
                    }
                    .disabled(profileList.isEmpty)
                } else {
                    Button("Done") {
                        editMode = .inactive
                    }
                }
            }
        }
        #endif
        #if os(iOS) || os(tvOS)
        .environment(\.editMode, $editMode)
        #endif
    }

    private func createImportProfileDialog(_ profile: LibboxProfileContent) {
        alert = Alert(
            title: Text("Import Profile"),
            message: Text("Are you sure to import profile \(profile.name)?"),
            primaryButton: .default(Text("Import")) {
                Task {
                    do {
                        try await profile.importProfile()
                    } catch {
                        alert = Alert(error)
                        return
                    }
                    await doReload()
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

    private func doReload() async {
        if ApplicationLibrary.inPreview {
            profileList = [
                ProfilePreview(Profile(id: 0, name: "profile local", type: .local, path: "")),
                ProfilePreview(Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0))),
            ]
        } else {
            defer {
                isLoading = false
            }
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
            } catch {
                alert = Alert(error)
                return
            }
        }
    }

    private func updateProfile(_ profile: Profile) async {
        await updateProfileBackground(profile)
        isUpdating = false
    }

    private nonisolated func updateProfileBackground(_ profile: Profile) async {
        do {
            _ = try await profile.updateRemoteProfile()
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }

    private func deleteProfile(_ profile: Profile) async {
        do {
            _ = try await ProfileManager.delete(profile)
        } catch {
            alert = Alert(error)
            return
        }
        await doReload()
    }

    private func moveProfile(from source: IndexSet, to destination: Int) {
        profileList.move(fromOffsets: source, toOffset: destination)
        for (index, profile) in profileList.enumerated() {
            profileList[index].order = UInt32(index)
            profile.origin.order = UInt32(index)
        }
        Task {
            do {
                try await ProfileManager.update(profileList.map(\.origin))
            } catch {
                alert = Alert(error)
            }
        }
    }

    private func deleteProfile(where profileIndex: IndexSet) {
        let profileToDelete = profileIndex.map { index in
            profileList[index].origin
        }
        profileList.remove(atOffsets: profileIndex)
        Task {
            do {
                _ = try await ProfileManager.delete(profileToDelete)
            } catch {
                alert = Alert(error)
            }
        }
    }

    public struct ProfileItem: View {
        private let parent: ProfileView
        @State private var profile: ProfilePreview
        public init(_ parent: ProfileView, _ profile: ProfilePreview) {
            self.parent = parent
            _profile = State(initialValue: profile)
        }

        public var body: some View {
            #if os(iOS) || os(macOS)
                if #available(iOS 16.0, macOS 13.0,*) {
                    body0.draggable(profile.origin)
                } else {
                    body0
                }
            #else
                body0
            #endif
        }

        @MainActor
        private var body0: some View {
            viewBuilder {
                #if !os(macOS)
                    NavigationLink {
                        EditProfileView().environmentObject(profile.origin)
                    } label: {
                        Text(profile.name)
                    }
                    .contextMenu {
                        ProfileShareButton(parent.$alert, profile.origin) {
                            Label("Share", systemImage: "square.and.arrow.up.fill")
                        }
                        if profile.type == .remote {
                            Button {
                                parent.isUpdating = true
                                Task {
                                    await parent.updateProfile(profile.origin)
                                    profile = ProfilePreview(profile.origin)
                                }
                            } label: {
                                Label("Update", systemImage: "arrow.clockwise")
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                await parent.deleteProfile(profile.origin)
                            }
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
                                Text("Last Updated: \(profile.origin.lastUpdatedString)").font(.caption)
                            }
                        }
                        HStack {
                            if profile.type == .remote {
                                Button {
                                    parent.isUpdating = true
                                    Task {
                                        await parent.updateProfile(profile.origin)
                                        profile = ProfilePreview(profile.origin)
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            ProfileShareButton(parent.$alert, profile.origin) {
                                Image(systemName: "square.and.arrow.up.fill")
                            }
                            Button {
                                parent.openWindow(id: EditProfileWindowView.windowID, value: profile.id)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            Button {
                                Task {
                                    await parent.deleteProfile(profile.origin)
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                            }
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
