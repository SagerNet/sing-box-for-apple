import Foundation
import Libbox
import Library
import Network
import QRCode
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
                ZStack {
                    if let importRemoteProfileRequest {
                        NavigationDestinationCompat(isPresented: $importRemoteProfilePresented) {
                            NewProfileView(importRemoteProfileRequest)
                        }
                    }
                    FormView {
                        #if os(iOS)
                            FormNavigationLink {
                                NewProfileView()
                            } label: {
                                Text("New Profile").foregroundColor(.accentColor)
                            }
                            .disabled(editMode.isEditing)
                        #elseif os(macOS)
                            FormNavigationLink {
                                NewProfileView()
                            } label: {
                                Text("New Profile")
                            }
                        #elseif os(tvOS)
                            Section {
                                FormNavigationLink {
                                    NewProfileView()
                                } label: {
                                    Text("New Profile").foregroundColor(.accentColor)
                                }
                                if ApplicationLibrary.inPreview || devicePickerSupports(.applicationService(name: "sing-box"), parameters: { .applicationService }) {
                                    FormNavigationLink {
                                        ImportProfileView()
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
                                        #if os(iOS) || os(tvOS)
                                            if editMode.isEditing == true {
                                                Text(profile.name)
                                            } else {
                                                ProfileItem(self, profile)
                                            }
                                        #else
                                            ProfileItem(self, profile)
                                        #endif
                                    }
                                }
                                .onMove(perform: moveProfile)
                                .onDelete(perform: deleteProfile)
                            }
                        }
                    }
                }
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
            Task {
                await doReload()
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton().disabled(profileList.isEmpty && !editMode.isEditing)
            }
        }
        #elseif os(tvOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if editMode == .inactive {
                    Button(action: {
                        editMode = .active
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(.accentColor)
                    .disabled(profileList.isEmpty)
                } else {
                    Button(action: {
                        editMode = .inactive
                    }) {
                        Image(systemName: "checkmark.square.fill")
                    }
                    .tint(.accentColor)
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
                importRemoteProfilePresented = true
            },
            secondaryButton: .cancel()
        )
    }

    private func doReload() async {
        defer {
            isLoading = false
        }
        if ApplicationLibrary.inPreview {
            profileList = [
                ProfilePreview(Profile(id: 0, name: "profile local", type: .local, path: "")),
                ProfilePreview(Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0))),
            ]
        } else {
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
            } catch {
                alert = Alert(error)
                return
            }
        }
        environments.emptyProfiles = profileList.isEmpty
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
        environments.profileUpdate.send()
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
            environments.profileUpdate.send()
        }
    }

    private func deleteProfile(where profileIndex: IndexSet) {
        let profileToDelete = profileIndex.map { index in
            profileList[index].origin
        }
        profileList.remove(atOffsets: profileIndex)
        environments.emptyProfiles = profileList.isEmpty
        Task {
            do {
                _ = try await ProfileManager.delete(profileToDelete)
            } catch {
                alert = Alert(error)
            }
            environments.profileUpdate.send()
        }
    }

    @MainActor
    public struct ProfileItem: View {
        private let parent: ProfileView
        @State private var profile: ProfilePreview
        @State private var shareLinkPresented = false

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

        private var body0: some View {
            viewBuilder {
                #if !os(macOS)
                    FormNavigationLink {
                        EditProfileView().environmentObject(profile.origin)
                    } label: {
                        Text(profile.name)
                    }
                    .sheet(isPresented: $shareLinkPresented) {
                        shareLinkView.padding()
                    }
                    .contextMenu {
                        ProfileShareButton(parent.$alert, profile.origin) {
                            Label("Share", systemImage: "square.and.arrow.up.fill")
                        }

                        if profile.type == .remote {
                            Button {
                                shareLinkPresented = true
                            } label: {
                                Label("Share URL as QR Code", systemImage: "qrcode")
                            }
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
                    FormNavigationLink {
                        EditProfileView().environmentObject(profile.origin)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                if profile.type == .remote {
                                    Spacer(minLength: 4)
                                    Text("Last Updated: \(profile.origin.lastUpdated!.myFormat)").font(.caption)
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
                                    .padding(.leading, 4)

                                    Button {
                                        shareLinkPresented = true
                                    } label: {
                                        Image(systemName: "qrcode")
                                    }
                                    .padding(.leading, 4)
                                    .popover(isPresented: $shareLinkPresented, arrowEdge: .bottom) {
                                        shareLinkView
                                    }
                                }
                                ProfileShareButton(parent.$alert, profile.origin) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                }
                                .padding(.leading, 4)
                                Button {
                                    Task {
                                        await parent.deleteProfile(profile.origin)
                                    }
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .padding([.leading, .trailing], 4)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                #endif
            }
        }

        private var shareLinkView: some View {
            #if os(iOS)
                viewBuilder {
                    if #available(iOS 16.0, *) {
                        shareLinkView0
                            .presentationDetents([.medium])
                            .presentationDragIndicator(.visible)
                    } else {
                        shareLinkView0
                    }
                }
            #elseif os(macOS)
                shareLinkView0
                    .frame(minWidth: 300, minHeight: 300)
            #else
                shareLinkView0
            #endif
        }

        private var foregroundColor: CGColor {
            #if canImport(UIKit)
                return UIColor.label.cgColor
            #elseif canImport(AppKit)
                return NSColor.labelColor.cgColor
            #endif
        }

        private var shareLinkView0: some View {
            QRCodeViewUI(
                content: LibboxGenerateRemoteProfileImportLink(profile.name, profile.remoteURL!),
                errorCorrection: .low,
                foregroundColor: foregroundColor,
                backgroundColor: CGColor(gray: 1.0, alpha: 0.0)
            )
        }
    }
}
