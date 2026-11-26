import Foundation
import Library
#if canImport(UIKit)
    import UIKit
#endif

@MainActor
public enum ProfileUpdateTask {
    private static var timer: Timer?
    #if os(iOS) || os(tvOS)
        private static var foregroundObserver: NSObjectProtocol?
    #endif

    public static func configure() async throws {
        #if os(iOS) || os(tvOS)
            if foregroundObserver == nil {
                foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                    Task { @MainActor in
                        do {
                            try await configure()
                        } catch {
                            NSLog("configure profile update task failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        #endif
        let profiles = try await ProfileManager.listAutoUpdateEnabled()
        let extensionProfileID = await extensionManagedProfileID()
        timer?.invalidate()
        timer = nil
        if profiles.isEmpty {
            return
        }
        var updateInterval = profiles.map { it in
            it.autoUpdateIntervalOrDefault
        }.min()!
        if updateInterval < Profile.minAutoUpdateInterval {
            updateInterval = Profile.minAutoUpdateInterval
        }
        let nextDate = profiles.filter { it in
            it.id != extensionProfileID
        }.map { it in
            dueDate(it)
        }.min() ?? Date(timeIntervalSinceNow: updateInterval)
        let newTimer = Timer(fire: max(nextDate, .now), interval: updateInterval, repeats: true) { _ in
            Task {
                await getAndUpdateProfiles()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private nonisolated static func dueDate(_ profile: Profile) -> Date {
        (profile.lastUpdated ?? .distantPast).addingTimeInterval(profile.autoUpdateIntervalOrDefault)
    }

    private nonisolated static func extensionManagedProfileID() async -> Int64? {
        #if os(iOS) || os(tvOS)
            if let extensionProfile = try? await ExtensionProfile.load(), await extensionProfile.status.isStarted {
                return await SharedPreferences.selectedProfileID.get()
            }
        #endif
        return nil
    }

    private nonisolated static func getAndUpdateProfiles() async {
        let profiles: [Profile]
        do {
            profiles = try await ProfileManager.listAutoUpdateEnabled()
        } catch {
            NSLog("profile update task failed: \(error.localizedDescription)")
            return
        }
        let extensionProfileID = await extensionManagedProfileID()
        for profile in profiles {
            if profile.id == extensionProfileID || dueDate(profile) > .now {
                continue
            }
            let profileName = profile.name
            do {
                try await profile.updateRemoteProfile()
                NSLog("Updated profile %@", profileName)
            } catch {
                NSLog("Update profile %@ failed: %@", profileName, error.localizedDescription)
            }
        }
    }
}
