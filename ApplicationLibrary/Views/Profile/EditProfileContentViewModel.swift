import Foundation
import Library
import SwiftUI

@MainActor
public final class EditProfileContentViewModel: BaseViewModel {
    @Published public var profile: Profile?
    @Published public var profileContent = ""
    @Published public var isChanged = false

    private let profileID: Int64?

    public init(profileID: Int64?) {
        self.profileID = profileID
        super.init()
        isLoading = true
    }

    public func markAsChanged() {
        isChanged = true
    }

    public func reset() {
        isLoading = true
        profile = nil
        profileContent = ""
        isChanged = false
        alert = nil
    }

    public func loadContent() async {
        do {
            try await loadContentBackground()
        } catch {
            alert = AlertState(error: error)
        }
        isLoading = false
    }

    private nonisolated func loadContentBackground() async throws {
        guard let profileID else {
            throw NSError(domain: "EditProfileContentViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Context destroyed")])
        }
        guard let profile = try await ProfileManager.get(profileID) else {
            throw NSError(domain: "EditProfileContentViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Profile missing")])
        }
        let profileContent = try profile.read()
        await MainActor.run {
            self.profile = profile
            self.profileContent = profileContent
        }
    }

    public func saveContent() async {
        guard let profile else {
            return
        }
        do {
            try await saveContentBackground(profile)
        } catch {
            alert = AlertState(error: error)
            return
        }
        isChanged = false
    }

    private nonisolated func saveContentBackground(_ profile: Profile) async throws {
        let profileContent = await profileContent
        try profile.write(profileContent)
    }
}
