
import Library
import SwiftUI

#if os(macOS)
    public struct EditProfileWindowView: View {
        public static let windowID = "edit-profile"

        private var profileID: Int64?

        public init(_ profileID: Int64?) {
            self.profileID = profileID
        }

        @Environment(\.dismiss) private var dismiss

        @State private var isLoading = true
        @State private var profile: Profile!
        @State private var errorPresented = false
        @State private var errorMessage = ""

        public var body: some View {
            viewBuilder {
                if isLoading {
                    ProgressView().onAppear {
                        Task.detached {
                            await doReload()
                        }
                    }
                    .alert(isPresented: $errorPresented) {
                        Alert(
                            title: Text("Error"),
                            message: Text(errorMessage),
                            dismissButton: .default(Text("Ok"), action: {
                                dismiss()
                            })
                        )
                    }
                } else {
                    EditProfileView().environmentObject(profile!)
                }
            }
            .onExitCommand {
                dismiss()
            }
        }

        private func doReload() async {
            guard let profileID else {
                errorMessage = "Context destroyed"
                errorPresented = true
                return
            }
            do {
                profile = try ProfileManager.get(profileID)
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
                return
            }
            if profile == nil {
                errorMessage = "Profile deleted"
                errorPresented = true
                return
            }
            isLoading = false
        }
    }
#endif
