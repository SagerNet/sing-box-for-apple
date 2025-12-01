import Libbox
import Library
import SwiftUI

@MainActor
public final class EditProfileViewModel: BaseViewModel {
    @Published public var isChanged = false
    @Published public var shareLinkPresented = false
    @Published public var shareLinkText: String?

    public func markAsChanged() {
        isChanged = true
    }

    public func updateProfile(_ profile: Profile, environments: ExtensionEnvironments) async {
        defer {
            isLoading = false
        }
        do {
            try await Task.sleep(nanoseconds: UInt64(100 * Double(NSEC_PER_MSEC)))
            try await profile.updateRemoteProfile()
            environments.profileUpdate.send()
        } catch {
            alert = Alert(error)
        }
    }

    public func deleteProfile(_ profile: Profile, environments: ExtensionEnvironments, dismiss: DismissAction) async {
        do {
            try await ProfileManager.delete(profile)
        } catch {
            alert = Alert(error)
            return
        }
        environments.profileUpdate.send()
        dismiss()
    }

    public func saveProfile(_ profile: Profile, environments: ExtensionEnvironments) async {
        do {
            _ = try await ProfileManager.update(profile)
            #if os(iOS) || os(tvOS)
                try UIProfileUpdateTask.configure()
            #else
                try await ProfileUpdateTask.configure()
            #endif
            try await profile.onProfileUpdated()
        } catch {
            alert = Alert(error)
            return
        }
        isChanged = false
        isLoading = false
        environments.profileUpdate.send()
    }
}
