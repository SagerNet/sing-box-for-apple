import Libbox
import Library
import SwiftUI

@MainActor
public struct ProfileActionToolbar: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile: Profile
    @ObservedObject private var viewModel: EditProfileViewModel

    public init(profile: Profile, viewModel: EditProfileViewModel) {
        self.profile = profile
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(iOS) || os(tvOS)
            iosBody
        #elseif os(macOS)
            macOSBody
        #endif
    }

    #if os(iOS) || os(tvOS)
        private var iosBody: some View {
            Section("Action") {
                if profile.type != .remote {
                    FormNavigationLink {
                        EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                    } label: {
                        Label("Edit Content", systemImage: "pencil")
                            .foregroundColor(.accentColor)
                    }
                } else {
                    FormNavigationLink {
                        EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                    } label: {
                        Label("View Content", systemImage: "doc.fill")
                            .foregroundColor(.accentColor)
                    }
                    FormButton {
                        viewModel.isLoading = true
                        Task {
                            await viewModel.updateProfile(profile, environments: environments)
                        }
                    } label: {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                    .foregroundColor(.accentColor)
                    .disabled(viewModel.isLoading)
                }
                FormButton(role: .destructive) {
                    Task {
                        await viewModel.deleteProfile(profile, environments: environments, dismiss: dismiss)
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .foregroundColor(.red)
            }
        }
    #endif

    #if os(macOS)
        private var macOSBody: some View {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 12) {
                    if profile.type != .remote {
                        NavigationLink {
                            EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                        } label: {
                            Text("Edit Content")
                        }
                    } else {
                        NavigationLink {
                            EditProfileContentView(EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
                        } label: {
                            Text("View Content")
                        }

                        Button {
                            viewModel.isLoading = true
                            Task {
                                await viewModel.updateProfile(profile, environments: environments)
                            }
                        } label: {
                            Text("Update")
                        }
                        .disabled(viewModel.isLoading)
                    }

                    Spacer()

                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteProfile(profile, environments: environments, dismiss: dismiss)
                        }
                    }
                    .foregroundColor(.red)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    #endif
}
