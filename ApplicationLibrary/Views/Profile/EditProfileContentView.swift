#if os(iOS) || os(macOS)
    import Foundation
    import Library
    import SwiftUI

    @MainActor
    public struct EditProfileContentView: View {
        public struct Context: Codable, Hashable {
            public let profileID: Int64
            public let readOnly: Bool
        }

        private let profileID: Int64?
        private let readOnly: Bool

        public init(_ context: Context?) {
            profileID = context?.profileID
            readOnly = context?.readOnly == true
        }

        @Environment(\.dismiss) private var dismiss

        @State private var isLoading = true
        @State private var profile: Profile!
        @State private var profileContent = ""
        @State private var isChanged = false
        @State private var alert: Alert?

        public var body: some View {
            viewBuilder {
                if isLoading {
                    ProgressView().onAppear {
                        Task {
                            await loadContent()
                        }
                    }
                } else {
                    viewBuilder {
                        if readOnly {
                            TextEditor(text: .constant(profileContent))
                        } else {
                            TextEditor(text: $profileContent)
                        }
                    }
                    .font(Font.system(.caption2, design: .monospaced))
                    .autocorrectionDisabled(true)
                    // https://stackoverflow.com/questions/66721935/swiftui-how-to-disable-the-smart-quotes-in-texteditor
                    // https://stackoverflow.com/questions/74034171/textfield-with-autocorrectiondisabled-still-shows-predictive-text-bar
                    .textContentType(.init(rawValue: ""))
                    #if os(iOS)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.none)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                    #elseif os(macOS)
                        .padding()
                    #endif
                        .onChangeCompat(of: profileContent) {
                            isChanged = true
                        }
                }
            }
            .alertBinding($alert)
            .navigationTitle(navigationTitle)
            #if os(macOS)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        if !readOnly {
                            Button {
                                Task {
                                    await saveContent()
                                }
                            } label: {
                                Label("Save", image: "save")
                            }
                            .disabled(!isChanged)
                        } else {
                            Button {
                                NSPasteboard.general.setString(profileContent, forType: .fileContents)
                            } label: {
                                Label("Copy", systemImage: "clipboard.fill")
                            }
                        }
                    }
                }
            #elseif os(iOS)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !readOnly {
                            Button("Save") {
                                Task {
                                    await saveContent()
                                }
                            }.disabled(!isChanged)
                        } else {
                            Button("Copy") {
                                UIPasteboard.general.string = profileContent
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        private var navigationTitle: String {
            if readOnly {
                return String(localized: "View Content")
            } else {
                return String(localized: "Edit Content")
            }
        }

        private func loadContent() async {
            do {
                try await loadContentBackground()
            } catch {
                alert = Alert(error)
            }
            isLoading = false
        }

        private nonisolated func loadContentBackground() async throws {
            guard let profileID else {
                throw NSError(domain: "Context destroyed", code: 0)
            }
            guard let profile = try await ProfileManager.get(profileID) else {
                throw NSError(domain: "Profile missing", code: 0)
            }
            let profileContent = try profile.read()
            await MainActor.run {
                self.profile = profile
                self.profileContent = profileContent
            }
        }

        private func saveContent() async {
            guard let profile else {
                return
            }
            do {
                try await saveContentBackground(profile)
            } catch {
                alert = Alert(error)
                return
            }
            isChanged = false
        }

        private nonisolated func saveContentBackground(_ profile: Profile) async throws {
            try await profile.write(profileContent)
        }
    }

#endif
