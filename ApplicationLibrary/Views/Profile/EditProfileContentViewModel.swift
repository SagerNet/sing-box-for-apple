import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class EditProfileContentViewModel: BaseViewModel {
    @Published public var profile: Profile?
    @Published public var profileContent = ""
    @Published public var isChanged = false
    @Published public var configurationError: String?

    private let profileID: Int64?
    private var validationTask: Task<Void, Never>?

    public init(profileID: Int64?) {
        self.profileID = profileID
        super.init()
        isLoading = true
    }

    public func markAsChanged() {
        isChanged = true
        scheduleValidation()
    }

    public func reset() {
        isLoading = true
        profile = nil
        profileContent = ""
        isChanged = false
        configurationError = nil
        validationTask?.cancel()
        validationTask = nil
        alert = nil
    }

    public func scheduleValidation() {
        configurationError = nil
        validationTask?.cancel()
        validationTask = Task {
            try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
            guard !Task.isCancelled else { return }
            await checkConfiguration()
        }
    }

    private func checkConfiguration() async {
        let content = profileContent
        if content.isEmpty { return }
        let errorDescription: String? = await BlockingIO.run {
            var error: NSError?
            LibboxCheckConfig(content, &error)
            return error?.localizedDescription
        }
        configurationError = errorDescription
    }

    public func formatConfiguration() async {
        let content = profileContent
        if content.isEmpty { return }
        do {
            let formatted: String? = try await BlockingIO.run {
                var error: NSError?
                let result = LibboxFormatConfig(content, &error)
                if let error {
                    throw error
                }
                return result?.value
            }
            if let formatted, formatted != content {
                profileContent = formatted
                isChanged = true
            }
        } catch {
            configurationError = error.localizedDescription
        }
    }

    public func dismissConfigurationError() {
        configurationError = nil
    }

    public func loadContent() async {
        do {
            try await loadContentBackground()
        } catch {
            alert = AlertState(action: "load profile content", error: error)
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
        let profileContent = try await profile.readAsync()
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
            alert = AlertState(action: "save profile content", error: error)
            return
        }
        isChanged = false
    }

    private nonisolated func saveContentBackground(_ profile: Profile) async throws {
        let profileContent = await profileContent
        try await profile.writeAsync(profileContent)
    }
}
