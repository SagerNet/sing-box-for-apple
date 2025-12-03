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
        #if os(iOS)
            iosBody
        #elseif os(tvOS)
            tvOSBody
        #elseif os(macOS)
            macOSBody
        #endif
    }

    #if os(iOS)
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
                }
            }
        }
    #endif

    #if os(tvOS)
        private var tvOSBody: some View {
            EmptyView()
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
                    }

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
