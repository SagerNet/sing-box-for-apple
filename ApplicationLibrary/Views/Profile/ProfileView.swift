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
    @StateObject private var viewModel = ProfileViewModel()

    #if os(tvOS)
        @Environment(\.devicePickerSupports) private var devicePickerSupports
    #endif

    public init() {}
    public var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView().onAppear {
                    viewModel.setEnvironments(environments)
                    Task {
                        await viewModel.doReload()
                    }
                }
            } else {
                ZStack {
                    if let importRemoteProfileRequest = viewModel.importRemoteProfileRequest {
                        NavigationDestinationCompat(isPresented: $viewModel.importRemoteProfilePresented) {
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
                            .disabled(viewModel.editMode.isEditing)
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
                        if viewModel.profileList.isEmpty {
                            Text("Empty profiles")
                        } else {
                            List {
                                ForEach(viewModel.profileList, id: \.id) { profile in
                                    Group {
                                        #if os(iOS) || os(tvOS)
                                            if viewModel.editMode.isEditing == true {
                                                Text(profile.name)
                                            } else {
                                                ProfileItem(viewModel, profile)
                                            }
                                        #else
                                            ProfileItem(viewModel, profile)
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
        .disabled(viewModel.isUpdating)
        .alertBinding($viewModel.alert, $viewModel.isLoading)
        .onAppear {
            if let profile = importProfile.wrappedValue {
                importProfile.wrappedValue = nil
                viewModel.createImportProfileDialog(profile)
            }
            if let remoteProfile = importRemoteProfile.wrappedValue {
                importRemoteProfile.wrappedValue = nil
                viewModel.createImportRemoteProfileDialog(remoteProfile)
            }
        }
        .onChangeCompat(of: importProfile.wrappedValue) { newValue in
            if let newValue {
                importProfile.wrappedValue = nil
                viewModel.createImportProfileDialog(newValue)
            }
        }
        .onChangeCompat(of: importRemoteProfile.wrappedValue) { newValue in
            if let newValue {
                importRemoteProfile.wrappedValue = nil
                viewModel.createImportRemoteProfileDialog(newValue)
            }
        }
        .onReceive(environments.profileUpdate) { _ in
            Task {
                await viewModel.doReload()
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton().disabled(viewModel.profileList.isEmpty && !viewModel.editMode.isEditing)
            }
        }
        #elseif os(tvOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.editMode == .inactive {
                    Button(action: {
                        viewModel.editMode = .active
                    }, label: {
                        Image(systemName: "square.and.pencil")
                    })
                    .tint(.accentColor)
                    .disabled(viewModel.profileList.isEmpty)
                } else {
                    Button(action: {
                        viewModel.editMode = .inactive
                    }, label: {
                        Image(systemName: "checkmark.square.fill")
                    })
                    .tint(.accentColor)
                }
            }
        }
        #endif
        #if os(iOS) || os(tvOS)
        .environment(\.editMode, $viewModel.editMode)
        #endif
    }

    private func moveProfile(from source: IndexSet, to destination: Int) {
        viewModel.moveProfile(from: source, to: destination)
    }

    private func deleteProfile(where profileIndex: IndexSet) {
        viewModel.deleteProfile(where: profileIndex)
    }

    @MainActor
    public struct ProfileItem: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @ObservedObject private var viewModel: ProfileViewModel
        @State private var profile: ProfilePreview
        @State private var shareLinkPresented = false

        public init(_ viewModel: ProfileViewModel, _ profile: ProfilePreview) {
            self.viewModel = viewModel
            _profile = State(initialValue: profile)
        }

        public var body: some View {
            #if os(iOS) || os(macOS)
                if #available(iOS 16.0, macOS 13.0, *) {
                    draggableBody.draggable(profile.origin)
                } else {
                    draggableBody
                }
            #else
                draggableBody
            #endif
        }

        private var draggableBody: some View {
            Group {
                #if !os(macOS)
                    FormNavigationLink {
                        EditProfileView().environmentObject(profile.origin)
                    } label: {
                        Text(profile.name)
                    }
                    .sheet(isPresented: $shareLinkPresented) {
                        QRCodeSheet(profileName: profile.name, remoteURL: profile.remoteURL!)
                    }
                    .contextMenu {
                        ProfileShareButton($viewModel.alert, profile.origin) {
                            Label("Share", systemImage: "square.and.arrow.up.fill")
                        }

                        if profile.type == .remote {
                            Button {
                                shareLinkPresented = true
                            } label: {
                                Label("Share URL as QR Code", systemImage: "qrcode")
                            }
                            Button {
                                viewModel.isUpdating = true
                                Task {
                                    await viewModel.updateProfile(profile.origin)
                                    profile = ProfilePreview(profile.origin)
                                }
                            } label: {
                                Label("Update", systemImage: "arrow.clockwise")
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteProfile(profile.origin)
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
                                        viewModel.isUpdating = true
                                        Task {
                                            await viewModel.updateProfile(profile.origin)
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
                                        QRCodeContentView(profileName: profile.name, remoteURL: profile.remoteURL!)
                                    }
                                }
                                ProfileShareButton($viewModel.alert, profile.origin) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                }
                                .padding(.leading, 4)
                                Button {
                                    Task {
                                        await viewModel.deleteProfile(profile.origin)
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
    }
}
