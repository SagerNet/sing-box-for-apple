import Foundation
import Libbox
import Library
import QRCode
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

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
        #if os(tvOS)
            .navigationDestination(isPresented: $viewModel.showNewProfile) {
                NewProfileMenuView()
                    .environmentObject(environments)
                    .onDisappear {
                        environments.profileUpdate.send()
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
            .navigationDestination(isPresented: $viewModel.showProfilePicker) {
                ProfilePickerSheet(
                    profileList: $profileList,
                    selectedProfileID: $selectedProfileID
                )
                .environmentObject(environments)
                .navigationTitle("Profiles")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
            }
            .navigationDestination(item: $viewModel.profileToEdit) { profile in
                EditProfileView()
                    .environmentObject(profile)
                    .environmentObject(environments)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
            .sheet(isPresented: $viewModel.showQRCode) {
                if let profile = selectedProfile, let remoteURL = profile.remoteURL {
                    QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
                }
            }
        #else
            .sheet(isPresented: $viewModel.showNewProfile, onDismiss: {
                    environments.profileUpdate.send()
                }, content: {
                    NewProfileNavigationView()
                        .environmentObject(environments)
                })
                .sheet(isPresented: $viewModel.showProfilePicker) {
                    profilePickerSheet
                }
                .sheet(item: $viewModel.profileToEdit) { profile in
                    editProfileSheet(for: profile)
                }
            #if os(iOS)
                .sheet(isPresented: $viewModel.showQRCode) {
                    if let profile = selectedProfile, let remoteURL = profile.remoteURL {
                        QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
                    }
                }
            #endif
        #endif
                .alert($viewModel.alert)
    }

    private var headerView: some View {
        HStack {
            DashboardCardHeader(icon: "doc.text.fill", title: "Profile")

            Spacer()

            Button {
                viewModel.showNewProfile = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .actionButtonStyle()
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
                    selectedItem: selectedProfile,
                    isPickerPresented: $viewModel.showProfilePicker
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

    private var actionButtonSpacing: CGFloat {
        #if os(tvOS)
            24
        #else
            12
        #endif
    }

    @ViewBuilder
    private func actionButtonsRow(for profile: ProfilePreview) -> some View {
        HStack(spacing: actionButtonSpacing) {
            editButton(for: profile)

            if profile.type == .remote {
                updateButton(for: profile)
            }

            shareMenu(for: profile)
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
    private func shareMenu(for profile: ProfilePreview) -> some View {
        #if os(tvOS)
            if profile.type == .remote {
                Menu {
                    Button {
                        viewModel.showQRCode = true
                    } label: {
                        Label("Share URL as QR Code", systemImage: "qrcode")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .actionButtonStyle()
            }
        #else
            Menu {
                Button {
                    viewModel.shareItemType = .file
                } label: {
                    Label("Share File", systemImage: "doc")
                }

                if profile.type == .remote {
                    Button {
                        viewModel.showQRCode = true
                    } label: {
                        Label("Share URL as QR Code", systemImage: "qrcode")
                    }
                }

                Button {
                    viewModel.shareItemType = .json
                } label: {
                    Label("Share Content JSON File", systemImage: "curlybraces")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
            }
            .menuIndicator(.hidden)
            .foregroundStyle(.primary)
            .menuStyle(.borderlessButton)
            .actionButtonStyle()
            .onChange(of: viewModel.shareItemType) { shareItemType in
                guard let shareItemType else { return }
                viewModel.shareItemType = nil
                shareProfile(profile, type: shareItemType)
            }
            #if os(macOS)
            .background(ViewAnchor { viewModel.shareButtonView = $0 })
            .popover(isPresented: $viewModel.showQRCode, arrowEdge: .bottom) {
                if let remoteURL = profile.remoteURL {
                    QRCodeContentView(profileName: profile.name, remoteURL: remoteURL)
                }
            }
            #endif
        #endif
    }

    #if !os(tvOS)
        private func shareProfile(_ profile: ProfilePreview, type: ShareItemType) {
            do {
                let url: URL
                switch type {
                case .file:
                    url = try profile.origin.toContent().generateShareFile()
                case .json:
                    url = try profile.origin.read().generateShareFile(name: "\(profile.name).json")
                }
                #if os(iOS)
                    presentShareController(url)
                #elseif os(macOS)
                    let anchorView = viewModel.shareButtonView ?? NSApp.keyWindow?.contentView ?? NSView()
                    NSSharingServicePicker(items: [url]).show(
                        relativeTo: .zero,
                        of: anchorView,
                        preferredEdge: .minY
                    )
                #endif
            } catch {
                viewModel.alert = AlertState(error: error)
            }
        }

        #if os(iOS)
            private func presentShareController(_ item: URL) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootViewController = windowScene.keyWindow?.rootViewController
                else {
                    return
                }
                var topViewController = rootViewController
                while let presented = topViewController.presentedViewController {
                    topViewController = presented
                }
                topViewController.present(
                    UIActivityViewController(activityItems: [item], applicationActivities: nil),
                    animated: true
                )
            }
        #endif
    #endif

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
                    Text(lastUpdated.relativeFormat)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    #if !os(tvOS)
        private var profilePickerSheet: some View {
            NavigationSheet(
                title: String(localized: "Profiles"),
                size: .large,
                content: {
                    ProfilePickerSheet(
                        profileList: $profileList,
                        selectedProfileID: $selectedProfileID
                    )
                    .environmentObject(environments)
                }
            )
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
            .modifier(OpaqueSheetBackground())
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
    #endif
}

// MARK: - ViewModel

extension ProfileCard {
    enum ShareItemType {
        case file
        case json
    }

    @MainActor
    class ViewModel: ObservableObject {
        @Published var showNewProfile = false
        @Published var showProfilePicker = false
        @Published var showQRCode = false
        @Published var isUpdating = false
        @Published var alert: AlertState?
        @Published var profileToEdit: Profile?
        @Published var shareItemType: ShareItemType?
        #if os(macOS)
            var shareButtonView: NSView?
        #endif

        func updateProfile(_ profile: Profile, environments: ExtensionEnvironments) async {
            defer { isUpdating = false }

            do {
                try await profile.updateRemoteProfile()
                environments.profileUpdate.send()
            } catch {
                alert = AlertState(
                    title: String(localized: "Update Failed"),
                    message: error.localizedDescription
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

        var body: some View {
            #if os(macOS)
                NavigationSheet {
                    NewProfileMenuView()
                        .environmentObject(environments)
                }
            #else
                NavigationStackCompat {
                    NewProfileMenuView()
                        .environmentObject(environments)
                }
                .presentationDetentsIfAvailable()
            #endif
        }
    }
}

// MARK: - OpaqueSheetBackground

#if os(iOS)
    private struct OpaqueSheetBackground: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 16.4, *) {
                content.presentationBackground(.regularMaterial)
            } else {
                content
            }
        }
    }

#elseif os(macOS)
    private struct OpaqueSheetBackground: ViewModifier {
        func body(content: Content) -> some View {
            content
        }
    }

    private struct ViewAnchor: NSViewRepresentable {
        let callback: (NSView) -> Void

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                callback(view)
            }
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}
    }
#else
    private struct OpaqueSheetBackground: ViewModifier {
        func body(content: Content) -> some View {
            content
        }
    }
#endif
