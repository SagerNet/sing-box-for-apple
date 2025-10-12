import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
final class ActiveDashboardViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var profileList: [ProfilePreview] = []
    @Published var selectedProfileID: Int64 = 0
    @Published var alert: Alert?
    @Published var selection = DashboardPage.overview
    @Published var systemProxyAvailable = false
    @Published var systemProxyEnabled = false

    var onEmptyProfilesChange: ((Bool) -> Void)?

    func reload() async {
        defer {
            isLoading = false
        }
        if ApplicationLibrary.inPreview {
            profileList = [
                ProfilePreview(Profile(id: 0, name: "profile local", type: .local, path: "")),
                ProfilePreview(Profile(id: 1, name: "profile remote", type: .remote, path: "", lastUpdated: Date(timeIntervalSince1970: 0))),
            ]
            systemProxyAvailable = true
            systemProxyEnabled = true
            selectedProfileID = 0

        } else {
            do {
                profileList = try await ProfileManager.list().map { ProfilePreview($0) }
                if profileList.isEmpty {
                    onEmptyProfilesChange?(true)
                    return
                }
                selectedProfileID = await SharedPreferences.selectedProfileID.get()
                if profileList.filter({ profile in
                    profile.id == selectedProfileID
                })
                .isEmpty {
                    selectedProfileID = profileList[0].id
                    await SharedPreferences.selectedProfileID.set(selectedProfileID)
                }

            } catch {
                alert = Alert(error)
                return
            }
        }
        onEmptyProfilesChange?(profileList.isEmpty)
    }

    nonisolated func reloadSystemProxy() async {
        do {
            let status = try LibboxNewStandaloneCommandClient()!.getSystemProxyStatus()
            await MainActor.run {
                systemProxyAvailable = status.available
                systemProxyEnabled = status.enabled
            }
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }

    func updateSelectedProfile() async {
        selectedProfileID = await SharedPreferences.selectedProfileID.get()
    }
}
