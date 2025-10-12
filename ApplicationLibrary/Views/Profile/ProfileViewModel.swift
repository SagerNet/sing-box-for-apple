import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public class ProfileViewModel: ObservableObject {
    @Published public var importRemoteProfileRequest: NewProfileView.ImportRequest?
    @Published public var importRemoteProfilePresented = false
    @Published public var isLoading = true
    @Published public var isUpdating = false
    @Published public var alert: Alert?
    @Published public var profileList: [ProfilePreview] = []

    #if os(iOS) || os(tvOS)
        @Published public var editMode = EditMode.inactive
    #endif

    private weak var environments: ExtensionEnvironments?

    public init() {}

    public func setEnvironments(_ environments: ExtensionEnvironments) {
        self.environments = environments
    }

    public func createImportProfileDialog(_ profile: LibboxProfileContent) {
        alert = Alert(
            title: Text("Import Profile"),
            message: Text("Are you sure to import profile \(profile.name)?"),
            primaryButton: .default(Text("Import")) {
                Task {
                    do {
                        try await profile.importProfile()
                    } catch {
                        self.alert = Alert(error)
                        return
                    }
                    await self.doReload()
                    self.environments?.emptyProfiles = self.profileList.isEmpty
                }
            },
            secondaryButton: .cancel()
        )
    }

    public func createImportRemoteProfileDialog(_ newValue: LibboxImportRemoteProfile) {
        importRemoteProfileRequest = .init(name: newValue.name, url: newValue.url)
        alert = Alert(
            title: Text("Import Remote Profile"),
            message: Text("Are you sure to import remote profile \(newValue.name)? You will connect to \(newValue.host) to download the configuration."),
            primaryButton: .default(Text("Import")) {
                self.importRemoteProfilePresented = true
            },
            secondaryButton: .cancel()
        )
    }

    public func doReload() async {
        defer {
            isLoading = false
        }
        if ApplicationLibrary.inPreview {
            profileList = [
                ProfilePreview(Profile(id: 0, name: "profile local", type: .local, path: "")),
                ProfilePreview(Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0))),
            ]
        } else {
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
            } catch {
                alert = Alert(error)
                return
            }
        }
        environments?.emptyProfiles = profileList.isEmpty
    }

    public func updateProfile(_ profile: Profile) async {
        await updateProfileBackground(profile)
        isUpdating = false
    }

    private nonisolated func updateProfileBackground(_ profile: Profile) async {
        do {
            _ = try await profile.updateRemoteProfile()
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }

    public func deleteProfile(_ profile: Profile) async {
        do {
            _ = try await ProfileManager.delete(profile)
            environments?.profileUpdate.send()
            environments?.emptyProfiles = profileList.isEmpty
        } catch {
            alert = Alert(error)
        }
    }

    public func moveProfile(from source: IndexSet, to destination: Int) {
        profileList.move(fromOffsets: source, toOffset: destination)
        for (index, profile) in profileList.enumerated() {
            profileList[index].order = UInt32(index)
            profile.origin.order = UInt32(index)
        }
        Task {
            do {
                try await ProfileManager.update(profileList.map(\.origin))
                environments?.profileUpdate.send()
            } catch {
                alert = Alert(error)
            }
        }
    }

    public func deleteProfile(where profileIndex: IndexSet) {
        let profileToDelete = profileIndex.map { index in
            profileList[index].origin
        }
        profileList.remove(atOffsets: profileIndex)
        Task {
            do {
                _ = try await ProfileManager.delete(profileToDelete)
                environments?.emptyProfiles = profileList.isEmpty
                environments?.profileUpdate.send()
            } catch {
                alert = Alert(error)
            }
        }
    }
}
