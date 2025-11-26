import Foundation
import Libbox
import Library
import QRCode
import SwiftUI

@MainActor
public struct ProfileCard: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = ViewModel()

    @Binding private var profileList: [ProfilePreview]
    @Binding private var selectedProfileID: Int64

    public init(
        profileList: Binding<[ProfilePreview]>,
        selectedProfileID: Binding<Int64>
    ) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
    }

    private var selectedProfile: ProfilePreview? {
        profileList.first { $0.id == selectedProfileID }
    }

    public var body: some View {
        DashboardCardView(title: "") {
            VStack(alignment: .leading, spacing: 16) {
                headerView
                profileSelectorView
            }
        }
        .disabled(viewModel.isUpdating)
        .sheet(isPresented: $viewModel.showNewProfile, onDismiss: {
            environments.profileUpdate.send()
        }) {
            NewProfileNavigationView()
                .environmentObject(environments)
        }
        .sheet(isPresented: $viewModel.showManageProfiles) {
            manageProfilesSheet
        }
        .sheet(item: $viewModel.profileToEdit) { profile in
            editProfileSheet(for: profile)
        }
        #if os(iOS) || os(tvOS)
        .sheet(isPresented: $viewModel.showQRCode) {
            if let profile = selectedProfile, let remoteURL = profile.remoteURL {
                QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
            }
        }
        #endif
        .alertBinding($viewModel.alert)
    }

    private var headerView: some View {
        HStack {
            Text("Profile")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Button {
                viewModel.showNewProfile = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .actionButtonStyle()

            if !profileList.isEmpty {
                Button {
                    viewModel.showManageProfiles = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .actionButtonStyle()
            }
        }
    }

    private var profileSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if profileList.isEmpty {
                Text("Empty profiles")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ProfileSelectorButton(
                    items: profileList,
                    selectedItem: selectedProfile,
                    onSelect: { selectedProfileID = $0 }
                )

                if let profile = selectedProfile {
                    VStack(alignment: .leading, spacing: 12) {
                        profileInfo(for: profile)
                        actionButtonsRow(for: profile)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtonsRow(for profile: ProfilePreview) -> some View {
        HStack(spacing: 12) {
            editButton(for: profile)

            if profile.type == .remote {
                updateButton(for: profile)
                qrCodeButton(for: profile)
            }

            ProfileShareButton($viewModel.alert, profile.origin) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .actionButtonStyle()
        }
    }

    @ViewBuilder
    private func editButton(for profile: ProfilePreview) -> some View {
        Button {
            viewModel.profileToEdit = profile.origin
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .actionButtonStyle()
    }

    @ViewBuilder
    private func updateButton(for profile: ProfilePreview) -> some View {
        Button {
            viewModel.isUpdating = true
            Task {
                await viewModel.updateProfile(profile.origin, environments: environments)
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16))
                .rotationEffect(.degrees(viewModel.isUpdating ? 360 : 0))
                .animation(
                    viewModel.isUpdating
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: viewModel.isUpdating
                )
        }
        .buttonStyle(.plain)
        .actionButtonStyle()
        .disabled(viewModel.isUpdating)
    }

    @ViewBuilder
    private func qrCodeButton(for profile: ProfilePreview) -> some View {
        #if os(iOS) || os(tvOS)
            Button {
                viewModel.showQRCode = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .actionButtonStyle()
        #elseif os(macOS)
            Button {
                viewModel.showQRCode = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .actionButtonStyle()
            .popover(isPresented: $viewModel.showQRCode, arrowEdge: .bottom) {
                if let remoteURL = profile.remoteURL {
                    QRCodeContentView(profileName: profile.name, remoteURL: remoteURL)
                }
            }
        #endif
    }

    @ViewBuilder
    private func profileInfo(for profile: ProfilePreview) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: profile.type == .remote ? "cloud.fill" : "doc.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(profile.type == .remote ? "Remote" : "Local")
                    .font(.caption)
                    .foregroundColor(.primary)
            }

            if profile.type == .remote, let lastUpdated = profile.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(lastUpdated.myFormat)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var manageProfilesSheet: some View {
        NavigationSheet(
            title: String(localized: "Manage profiles"),
            showDoneButton: true,
            onDismiss: { viewModel.showManageProfiles = false }
        ) {
            ManageProfilesView()
                .environmentObject(environments)
        }
    }

    @ViewBuilder
    private func editProfileSheet(for profile: Profile) -> some View {
        #if os(macOS)
            NavigationSheet {
                EditProfileView()
                    .environmentObject(profile)
                    .environmentObject(environments)
            }
            .frame(minWidth: 500, minHeight: 400)
        #else
            NavigationSheet(title: "Edit Profile") {
                EditProfileView()
                    .environmentObject(profile)
                    .environmentObject(environments)
            }
        #endif
    }
}

// MARK: - ViewModel

extension ProfileCard {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var showNewProfile = false
        @Published var showManageProfiles = false
        @Published var showQRCode = false
        @Published var isUpdating = false
        @Published var alert: Alert?
        @Published var profileToEdit: Profile?

        func updateProfile(_ profile: Profile, environments: ExtensionEnvironments) async {
            defer { isUpdating = false }

            do {
                try await profile.updateRemoteProfile()
                environments.profileUpdate.send()
            } catch {
                alert = Alert(
                    title: Text("Update Failed"),
                    message: Text(error.localizedDescription)
                )
            }
        }
    }
}

// MARK: - NewProfileNavigationView

extension ProfileCard {
    @MainActor
    struct NewProfileNavigationView: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @State private var createdProfile: Profile?

        var body: some View {
            #if os(macOS)
                macOSBody
            #else
                iOSBody
            #endif
        }

        #if os(macOS)
            @ViewBuilder
            private var macOSBody: some View {
                if let profile = createdProfile {
                    EditProfileView()
                        .environmentObject(profile)
                        .environmentObject(environments)
                } else {
                    NewProfileView { profile in
                        createdProfile = profile
                    }
                    .environmentObject(environments)
                }
            }
        #else
            private var iOSBody: some View {
                NavigationStackCompat {
                    if let profile = createdProfile {
                        EditProfileView()
                            .environmentObject(profile)
                            .environmentObject(environments)
                    } else {
                        NewProfileView { profile in
                            createdProfile = profile
                        }
                        .environmentObject(environments)
                        #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                        #endif
                    }
                }
                .presentationDetentsIfAvailable()
            }
        #endif
    }
}

// MARK: - ManageProfilesView

extension ProfileCard {
    @MainActor
    struct ManageProfilesView: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @StateObject private var viewModel = ProfileViewModel()

        var body: some View {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            viewModel.setEnvironments(environments)
                            Task {
                                await viewModel.doReload()
                            }
                        }
                } else {
                    FormView {
                        if viewModel.profileList.isEmpty {
                            Text("Empty profiles")
                        } else {
                            List {
                                ForEach(viewModel.profileList, id: \.id) { profile in
                                    ManageProfileItem(viewModel, profile)
                                }
                                .onMove(perform: moveProfile)
                                #if os(macOS)
                                    .onDelete(perform: deleteProfile)
                                #endif
                            }
                            #if os(iOS) || os(tvOS)
                            .environment(\.editMode, .constant(.active))
                            .deleteDisabled(true)
                            #endif
                        }
                    }
                }
            }
            .disabled(viewModel.isUpdating)
            .alertBinding($viewModel.alert, $viewModel.isLoading)
            .onReceive(environments.profileUpdate) { _ in
                Task {
                    await viewModel.doReload()
                }
            }
        }

        private func moveProfile(from source: IndexSet, to destination: Int) {
            viewModel.moveProfile(from: source, to: destination)
        }

        private func deleteProfile(where profileIndex: IndexSet) {
            viewModel.deleteProfile(where: profileIndex)
        }
    }

    @MainActor
    struct ManageProfileItem: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @ObservedObject private var viewModel: ProfileViewModel
        @State private var profile: ProfilePreview
        @State private var shareLinkPresented = false

        init(_ viewModel: ProfileViewModel, _ profile: ProfilePreview) {
            self.viewModel = viewModel
            _profile = State(initialValue: profile)
        }

        var body: some View {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading) {
                    Text(profile.name)
                    #if os(macOS)
                        if profile.type == .remote {
                            Spacer(minLength: 4)
                            Text("Last Updated: \(profile.origin.lastUpdated!.myFormat)").font(.caption)
                        }
                    #endif
                }

                Spacer()

                HStack(spacing: 8) {
                    if profile.type == .remote {
                        Button {
                            viewModel.isUpdating = true
                            Task {
                                await viewModel.updateProfile(profile.origin)
                                profile = ProfilePreview(profile.origin)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16))
                                .rotationEffect(.degrees(viewModel.isUpdating ? 360 : 0))
                                .animation(
                                    viewModel.isUpdating
                                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                                        : .default,
                                    value: viewModel.isUpdating
                                )
                        }
                        .buttonStyle(.plain)
                        .actionButtonStyle()
                        .disabled(viewModel.isUpdating)

                        Button {
                            shareLinkPresented = true
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .actionButtonStyle()
                        #if os(macOS)
                            .popover(isPresented: $shareLinkPresented, arrowEdge: .bottom) {
                                QRCodeContentView(profileName: profile.name, remoteURL: profile.remoteURL!)
                            }
                        #elseif os(iOS) || os(tvOS)
                            .sheet(isPresented: $shareLinkPresented) {
                                QRCodeSheet(profileName: profile.name, remoteURL: profile.remoteURL!)
                            }
                        #endif
                    }

                    ShareButtonCompat($viewModel.alert) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                    } itemURL: {
                        try profile.origin.toContent().generateShareFile()
                    }
                    .actionButtonStyle()

                    Button {
                        Task {
                            await viewModel.deleteProfile(profile.origin)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .actionButtonStyle()
                }
            }
            #if os(macOS)
            .padding(.vertical, 4)
            #endif
        }
    }
}
