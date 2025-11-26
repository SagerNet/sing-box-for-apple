import Libbox
import Library
import SwiftUI

@MainActor
public struct ProfileActionToolbar: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
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
                        Button("Edit Content") {
                            openWindow(value: EditProfileContentView.Context(profileID: profile.id!, readOnly: false))
                        }
                    } else {
                        Button("View Content") {
                            openWindow(value: EditProfileContentView.Context(profileID: profile.id!, readOnly: true))
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

                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteProfile(profile, environments: environments, dismiss: dismiss)
                        }
                    }
                    .foregroundColor(.red)

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }

                    Button("Save") {
                        viewModel.isLoading = true
                        Task {
                            await viewModel.saveProfile(profile, environments: environments)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || !viewModel.isChanged)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    #endif
}
