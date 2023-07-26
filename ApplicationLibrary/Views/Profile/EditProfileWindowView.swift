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
        @State private var alert: Alert?

        public var body: some View {
            viewBuilder {
                if isLoading {
                    ProgressView().onAppear {
                        Task.detached {
                            await doReload()
                        }
                    }
                } else {
                    EditProfileView().environmentObject(profile!)
                }
            }
            .alertBinding($alert)
            .onExitCommand {
                dismiss()
            }
        }

        private func doReload() async {
            guard let profileID else {
                alert = Alert(errorMessage: "Context destroyed")
                return
            }
            do {
                profile = try ProfileManager.get(profileID)
            } catch {
                alert = Alert(error)
                return
            }
            if profile == nil {
                alert = Alert(errorMessage: "Profile deleted")
                return
            }
            isLoading = false
        }
    }
#endif
